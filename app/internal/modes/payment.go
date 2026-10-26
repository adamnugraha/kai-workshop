package modes

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"

	"relnusa/internal/bank"
	"relnusa/internal/breaker"
	"relnusa/internal/config"
	"relnusa/internal/obs"
	"relnusa/internal/store"

	"net/http"
)

const paymentGroup = "payment-workers"

var (
	paymentAttempts = obs.NewCounterVec("payment_attempts_total", "Payment processing attempts by outcome.", "outcome")
	circuitState    = obs.NewGauge("payment_circuit_state", "Bank circuit breaker: 0 closed, 1 half-open, 2 open.")
	queueLength     = obs.NewGauge("payment_queue_length", "Entries in the payment stream.")
	queuePending    = obs.NewGauge("payment_queue_pending", "Payment jobs delivered but not yet completed.")
)

// PaymentWorker takes HELD bookings from the queue and charges the bank
// with a short timeout, behind a circuit breaker. Failed jobs stay pending
// and are retried; the bank's idempotency key prevents double charges.
func PaymentWorker(ctx context.Context) error {
	pool, err := openDB(ctx, 20)
	if err != nil {
		return err
	}
	defer pool.Close()
	rdb := openRedis()
	defer rdb.Close()

	bankClient := bank.New(config.Str("BANK_URL", "http://banksim.bank:8080"), 0)
	bankTimeout := config.Millis("BANK_TIMEOUT_MS", 800*time.Millisecond)
	concurrency := config.Int("WORKER_CONCURRENCY", 16)
	consumer, _ := os.Hostname()
	if consumer == "" {
		consumer = fmt.Sprintf("worker-%d", time.Now().UnixNano())
	}
	for _, o := range []string{"success", "failure", "timeout", "circuit_open", "error"} {
		paymentAttempts.WithLabelValues(o)
	}
	br := breaker.New(20, 10, 0.5, config.Millis("BREAKER_OPEN_MS", 10*time.Second), 3, func(s breaker.State) {
		circuitState.Set(float64(s))
		slog.Warn("bank circuit breaker changed state", "state", s.String())
	})

	ensureGroup := func() {
		err := rdb.XGroupCreateMkStream(ctx, paymentStream, paymentGroup, "0").Err()
		if err != nil && !strings.Contains(err.Error(), "BUSYGROUP") {
			slog.Warn("create consumer group", "err", err)
		}
	}
	ensureGroup()

	handle := func(msg redis.XMessage) {
		id, _ := msg.Values["booking_id"].(string)
		ack := func() { _ = rdb.XAck(ctx, paymentStream, paymentGroup, msg.ID).Err() }
		if id == "" {
			ack()
			return
		}
		status, amount, err := store.PaymentInfo(ctx, pool, id)
		if errors.Is(err, store.ErrNotFound) {
			ack() // booking table was reset
			return
		}
		if err != nil {
			paymentAttempts.WithLabelValues("error").Inc()
			return // stays pending, retried later
		}
		if status != "HELD" {
			ack() // already paid or expired
			return
		}
		if !br.Allow() {
			paymentAttempts.WithLabelValues("circuit_open").Inc()
			return
		}
		c, cancel := context.WithTimeout(ctx, bankTimeout)
		_, err = bankClient.Charge(c, id, amount)
		cancel()
		if err != nil {
			br.Record(true)
			if bank.IsTimeout(err) {
				paymentAttempts.WithLabelValues("timeout").Inc()
			} else {
				paymentAttempts.WithLabelValues("failure").Inc()
			}
			return
		}
		br.Record(false)
		if _, err := store.MarkPaid(ctx, pool, id); err != nil {
			paymentAttempts.WithLabelValues("error").Inc()
			return
		}
		paymentAttempts.WithLabelValues("success").Inc()
		ack()
	}

	sem := make(chan struct{}, concurrency)
	dispatch := func(m redis.XMessage) {
		sem <- struct{}{}
		go func() {
			defer func() { <-sem }()
			handle(m)
		}()
	}

	var lastRead atomic.Int64
	// New jobs.
	go func() {
		for ctx.Err() == nil {
			res, err := rdb.XReadGroup(ctx, &redis.XReadGroupArgs{
				Group: paymentGroup, Consumer: consumer, Streams: []string{paymentStream, ">"},
				Count: int64(concurrency), Block: 2 * time.Second,
			}).Result()
			lastRead.Store(time.Now().Unix())
			if errors.Is(err, redis.Nil) {
				continue
			}
			if err != nil {
				if strings.Contains(err.Error(), "NOGROUP") {
					ensureGroup()
				} else if ctx.Err() == nil {
					slog.Warn("read payment stream", "err", err)
				}
				time.Sleep(time.Second)
				continue
			}
			for _, s := range res {
				for _, m := range s.Messages {
					dispatch(m)
				}
			}
		}
	}()
	// Retries: claim jobs that have been pending for a while, including
	// jobs left behind by a worker that died.
	go func() {
		t := time.NewTicker(time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
			}
			if br.State() == breaker.Open {
				continue
			}
			start := "0-0"
			for i := 0; i < 10; i++ {
				msgs, next, err := rdb.XAutoClaim(ctx, &redis.XAutoClaimArgs{
					Stream: paymentStream, Group: paymentGroup, Consumer: consumer,
					MinIdle: 5 * time.Second, Start: start, Count: 100,
				}).Result()
				if err != nil {
					break
				}
				for _, m := range msgs {
					dispatch(m)
				}
				if next == "0-0" || len(msgs) == 0 {
					break
				}
				start = next
			}
		}
	}()
	// Queue depth metrics.
	go func() {
		t := time.NewTicker(2 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
			}
			if n, err := rdb.XLen(ctx, paymentStream).Result(); err == nil {
				queueLength.Set(float64(n))
			}
			if p, err := rdb.XPending(ctx, paymentStream, paymentGroup).Result(); err == nil {
				queuePending.Set(float64(p.Count))
			}
			// Trim acknowledged history so the stream does not grow forever.
			_ = rdb.XTrimMaxLenApprox(ctx, paymentStream, 200000, 0).Err()
		}
	}()

	mux := http.NewServeMux()
	ready := func(c context.Context) error { return rdb.Ping(c).Err() }
	return obs.Run(ctx, mux, ready)
}
