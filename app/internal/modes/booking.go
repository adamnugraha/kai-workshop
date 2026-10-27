package modes

import (
	"context"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"

	"relnusa/internal/config"
	"relnusa/internal/httpx"
	"relnusa/internal/obs"
	"relnusa/internal/store"
)

const paymentStream = "payments"

var (
	enqueueFailures = obs.NewCounterVec("booking_enqueue_failures_total", "Payment jobs that could not be queued.")
	holdsReleased   = obs.NewCounterVec("booking_holds_expired_total", "Seat holds released because payment did not complete in time.")
	bookingOutcomes = obs.NewCounterVec("booking_outcomes_total", "Booking requests by outcome.", "outcome")
)

// Booking reserves seats with a short transaction and hands payment to a
// queue, so a slow bank never holds a database lock.
func Booking(ctx context.Context) error {
	pool, err := openDB(ctx, 30)
	if err != nil {
		return err
	}
	defer pool.Close()
	rdb := openRedis()
	defer rdb.Close()

	holdFor := config.Millis("HOLD_MS", 10*time.Minute)
	faultRate := config.Float("FAULT_ERROR_RATE", 0)
	faultLatency := config.Millis("FAULT_LATENCY_MS", 0)
	if faultRate > 0 || faultLatency > 0 {
		slog.Warn("fault injection active", "error_rate", faultRate, "latency", faultLatency.String())
	}
	for _, o := range []string{"held", "replayed", "sold_out", "error", "fault"} {
		bookingOutcomes.WithLabelValues(o)
	}
	enqueueFailures.WithLabelValues()
	holdsReleased.WithLabelValues()

	var migrated atomic.Bool
	go func() {
		store.WaitAndMigrate(ctx, pool)
		migrated.Store(true)
		reap := time.NewTicker(15 * time.Second)
		inv := time.NewTicker(time.Hour)
		defer reap.Stop()
		defer inv.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-reap.C:
				n, err := store.ExpireHolds(ctx, pool)
				if err != nil {
					slog.Warn("expire holds", "err", err)
				} else if n > 0 {
					holdsReleased.WithLabelValues().Add(float64(n))
					slog.Info("released expired holds", "seats", n)
				}
			case <-inv.C:
				_ = store.EnsureInventory(ctx, pool)
			}
		}
	}()

	mux := http.NewServeMux()
	obs.Handle(mux, "POST /api/bookings", "/api/bookings", func(w http.ResponseWriter, r *http.Request) {
		if faultLatency > 0 {
			time.Sleep(faultLatency)
		}
		if faultRate > 0 && rand.Float64() < faultRate {
			bookingOutcomes.WithLabelValues("fault").Inc()
			httpx.Error(w, http.StatusInternalServerError, "internal", "internal error (version "+obs.Version+")")
			return
		}
		req, err := httpx.ParseBooking(r)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_request", err.Error())
			return
		}
		b, replayed, err := store.Hold(r.Context(), pool, req.TrainID, req.Date, req.Passenger, r.Header.Get("Idempotency-Key"), holdFor)
		if err != nil {
			if err == store.ErrSoldOut {
				bookingOutcomes.WithLabelValues("sold_out").Inc()
			} else {
				bookingOutcomes.WithLabelValues("error").Inc()
			}
			storeErr(w, err)
			return
		}
		if replayed {
			bookingOutcomes.WithLabelValues("replayed").Inc()
			httpx.JSON(w, http.StatusOK, map[string]any{"booking": b, "replayed": true,
				"message": "We have already received this request; here is your booking."})
			return
		}
		if err := enqueue(r.Context(), rdb, b); err != nil {
			enqueueFailures.WithLabelValues().Inc()
			slog.Error("enqueue payment", "err", err, "booking", b.ID)
		}
		bookingOutcomes.WithLabelValues("held").Inc()
		httpx.JSON(w, http.StatusAccepted, map[string]any{"booking": b,
			"message": "Your seat is secured. Your payment is being processed."})
	})
	obs.Handle(mux, "GET /api/bookings/{id}", "/api/bookings/{id}", func(w http.ResponseWriter, r *http.Request) {
		b, err := store.GetBooking(r.Context(), pool, r.PathValue("id"))
		if err != nil {
			storeErr(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{"booking": b})
	})

	ready := func(c context.Context) error {
		if !migrated.Load() {
			return fmt.Errorf("database not migrated yet")
		}
		return nil
	}
	return obs.Run(ctx, mux, ready)
}

func enqueue(ctx context.Context, rdb *redis.Client, b store.Booking) error {
	args := &redis.XAddArgs{Stream: paymentStream, Values: map[string]any{"booking_id": b.ID, "amount": b.Amount}}
	err := rdb.XAdd(ctx, args).Err()
	if err != nil {
		time.Sleep(100 * time.Millisecond)
		err = rdb.XAdd(ctx, args).Err()
	}
	return err
}
