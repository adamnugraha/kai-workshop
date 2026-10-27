package modes

import (
	"bytes"
	"context"
	"errors"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"sync"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"golang.org/x/time/rate"

	"relnusa/internal/bank"
	"relnusa/internal/config"
	"relnusa/internal/httpx"
	"relnusa/internal/obs"
	"relnusa/internal/web"
)

var (
	waitingRoom = obs.NewCounterVec("waiting_room_requests_total", "Booking requests at the virtual waiting room, by outcome.", "outcome")
	retries     = obs.NewCounterVec("gateway_upstream_retries_total", "Upstream calls retried after a connection error.", "upstream")
)

// Gateway serves the web UI, routes API calls to the services and runs the
// virtual waiting room in front of booking.
func Gateway(ctx context.Context) error {
	timeout := config.Millis("UPSTREAM_TIMEOUT_MS", 5*time.Second)
	searchProxy := newProxy("search", config.Str("SEARCH_URL", "http://search:8080"), timeout)
	bookingProxy := newProxy("booking", config.Str("BOOKING_URL", "http://booking:8080"), timeout)

	// Admission rate per gateway replica. Requests above it get a queue
	// position instead of an error, and the page retries by itself.
	limiter := rate.NewLimiter(rate.Limit(config.Float("ADMIT_RATE", 60)), config.Int("ADMIT_BURST", 30))
	queue := &recentCounter{}
	waitingRoom.WithLabelValues("admitted")
	waitingRoom.WithLabelValues("queued")

	mux := http.NewServeMux()
	web.Register(mux)
	obs.Handle(mux, "GET /api/info", "/api/info", infoHandler("modern"))
	obs.Handle(mux, "GET /api/stations", "/api/stations", searchProxy.ServeHTTP)
	obs.Handle(mux, "GET /api/search", "/api/search", searchProxy.ServeHTTP)
	obs.Handle(mux, "GET /api/bookings/{id}", "/api/bookings/{id}", bookingProxy.ServeHTTP)
	obs.Handle(mux, "POST /api/bookings", "/api/bookings", func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow() {
			waitingRoom.WithLabelValues("queued").Inc()
			pos := queue.add()
			httpx.JSON(w, http.StatusOK, map[string]any{
				"status":         "QUEUED",
				"position":       pos,
				"retry_after_ms": 1500 + rand.IntN(1500),
				"message":        "You are in the virtual queue. Please keep this page open; we will retry automatically.",
			})
			return
		}
		waitingRoom.WithLabelValues("admitted").Inc()
		bookingProxy.ServeHTTP(w, r)
	})
	return obs.Run(ctx, mux, nil)
}

func newProxy(name, target string, timeout time.Duration) *httputil.ReverseProxy {
	u, err := url.Parse(target)
	if err != nil {
		panic(err)
	}
	base := &http.Transport{
		DialContext:           (&net.Dialer{Timeout: time.Second, KeepAlive: 30 * time.Second}).DialContext,
		MaxIdleConns:          256,
		MaxIdleConnsPerHost:   32, // small pool so new pods (after scaling) quickly get connections
		IdleConnTimeout:       10 * time.Second,
		ResponseHeaderTimeout: timeout,
	}
	retries.WithLabelValues(name)
	return &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.SetURL(u)
			pr.SetXForwarded()
		},
		Transport: &retryTransport{name: name, next: otelhttp.NewTransport(base)},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			switch {
			case errors.Is(err, context.Canceled):
				return
			case bank.IsTimeout(err):
				httpx.Error(w, http.StatusGatewayTimeout, "upstream_timeout", "the service took too long to respond")
			default:
				httpx.Error(w, http.StatusBadGateway, "upstream_unavailable", "the service is temporarily unavailable")
			}
		},
	}
}

// retryTransport retries once when the connection to a pod could not be
// opened (for example the pod's node just died). It only retries requests
// that are safe to repeat: GETs, and POSTs that carry an Idempotency-Key.
type retryTransport struct {
	name string
	next http.RoundTripper
}

func (t *retryTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	retryable := req.Method == http.MethodGet || (req.Method == http.MethodPost && req.Header.Get("Idempotency-Key") != "")
	var body []byte
	if retryable && req.Body != nil && req.Body != http.NoBody {
		b, err := io.ReadAll(io.LimitReader(req.Body, 64<<10))
		_ = req.Body.Close()
		if err != nil {
			return nil, err
		}
		body = b
		req.Body = io.NopCloser(bytes.NewReader(body))
		req.GetBody = func() (io.ReadCloser, error) { return io.NopCloser(bytes.NewReader(body)), nil }
		req.ContentLength = int64(len(body))
	}
	resp, err := t.next.RoundTrip(req)
	if err == nil || !retryable || req.Context().Err() != nil || !isDialError(err) {
		return resp, err
	}
	retries.WithLabelValues(t.name).Inc()
	time.Sleep(50 * time.Millisecond)
	again := req.Clone(req.Context())
	if body != nil {
		again.Body = io.NopCloser(bytes.NewReader(body))
	}
	return t.next.RoundTrip(again)
}

func isDialError(err error) bool {
	var op *net.OpError
	return errors.As(err, &op) && op.Op == "dial"
}

// recentCounter counts events in the last few seconds; it gives the waiting
// room a rough "people ahead of you" number.
type recentCounter struct {
	mu      sync.Mutex
	buckets [4]int64
	stamps  [4]int64
}

func (c *recentCounter) add() int64 {
	now := time.Now().Unix()
	c.mu.Lock()
	defer c.mu.Unlock()
	i := now % 4
	if c.stamps[i] != now {
		c.stamps[i] = now
		c.buckets[i] = 0
	}
	c.buckets[i]++
	var total int64
	for j := range c.buckets {
		if c.stamps[j] >= now-2 {
			total += c.buckets[j]
		}
	}
	return total
}
