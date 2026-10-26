// Package obs wires logging, Prometheus metrics, OpenTelemetry tracing and
// the HTTP server lifecycle (health, readiness, graceful shutdown).
package obs

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"

	"relnusa/internal/config"
)

var (
	requests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "HTTP requests handled, by service, route, method and status code.",
	}, []string{"service", "route", "method", "code"})

	duration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request latency.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10, 20},
	}, []string{"service", "route", "method"})

	inflight = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "http_requests_in_flight",
		Help: "Requests currently being handled.",
	}, []string{"service"})

	buildInfo = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "relnusa_build_info",
		Help: "Build and mode information.",
	}, []string{"service", "version"})
)

// Version is the application version shown in responses and metrics.
var Version = config.Str("APP_VERSION", "v1")

// Service is the name of this process (monolith, gateway, search, ...).
var Service = "relnusa"

// Setup configures the logger and build info. Call once at startup.
func Setup(service string) {
	Service = service
	h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	slog.SetDefault(slog.New(h).With("service", service, "version", Version))
	buildInfo.WithLabelValues(service, Version).Set(1)
}

// InitTracing sets up OTLP/HTTP trace export when OTEL_EXPORTER_OTLP_ENDPOINT
// is set. It returns a shutdown function.
func InitTracing(ctx context.Context) func(context.Context) error {
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" && os.Getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") == "" {
		slog.Info("tracing disabled (no OTLP endpoint)")
		return func(context.Context) error { return nil }
	}
	exp, err := otlptracehttp.New(ctx)
	if err != nil {
		slog.Error("tracing exporter", "err", err)
		return func(context.Context) error { return nil }
	}
	res, _ := resource.New(ctx,
		resource.WithAttributes(
			attribute.String("service.name", Service),
			attribute.String("service.version", Version),
			attribute.String("service.namespace", "relnusa"),
		),
		resource.WithFromEnv(),
		resource.WithHost(),
	)
	ratio := config.Float("TRACE_SAMPLE_RATIO", 0.2)
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp, sdktrace.WithMaxQueueSize(8192), sdktrace.WithMaxExportBatchSize(1024)),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(ratio))),
	)
	otel.SetTracerProvider(tp)
	slog.Info("tracing enabled", "sample_ratio", ratio)
	return tp.Shutdown
}

// Tracer returns a tracer for manual spans.
func Tracer() trace.Tracer { return otel.Tracer("relnusa") }

type recorder struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (r *recorder) WriteHeader(code int) {
	if !r.wrote {
		r.status = code
		r.wrote = true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *recorder) Write(b []byte) (int, error) {
	if !r.wrote {
		r.status = http.StatusOK
		r.wrote = true
	}
	return r.ResponseWriter.Write(b)
}

func (r *recorder) Flush() {
	if f, ok := r.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// Handle registers an instrumented handler. pattern is a Go ServeMux
// pattern such as "GET /api/bookings/{id}"; route is the metric label.
func Handle(mux *http.ServeMux, pattern, route string, h http.HandlerFunc) {
	instrumented := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		g := inflight.WithLabelValues(Service)
		g.Inc()
		rec := &recorder{ResponseWriter: w, status: http.StatusOK}
		defer func() {
			g.Dec()
			code := rec.status
			if r.Context().Err() != nil && !rec.wrote {
				code = 499 // client went away before we answered
			}
			requests.WithLabelValues(Service, route, r.Method, strconv.Itoa(code)).Inc()
			duration.WithLabelValues(Service, route, r.Method).Observe(time.Since(start).Seconds())
		}()
		w.Header().Set("X-App-Version", Version)
		w.Header().Set("X-Served-By", Service)
		h(rec, r)
	})
	mux.Handle(pattern, otelhttp.NewHandler(instrumented, pattern))
}

// Run serves mux on :PORT with /healthz, /readyz and /metrics, and shuts
// down gracefully on SIGTERM: readiness turns red first so Kubernetes stops
// sending traffic, then in-flight requests are allowed to finish.
func Run(ctx context.Context, mux *http.ServeMux, ready func(context.Context) error) error {
	var stopping atomic.Bool
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if stopping.Load() {
			http.Error(w, "shutting down", http.StatusServiceUnavailable)
			return
		}
		if ready != nil {
			c, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()
			if err := ready(c); err != nil {
				http.Error(w, "not ready: "+err.Error(), http.StatusServiceUnavailable)
				return
			}
		}
		_, _ = w.Write([]byte("ready"))
	})
	mux.Handle("GET /metrics", promhttp.Handler())

	addr := ":" + config.Str("PORT", "8080")
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 90 * time.Second}
	errCh := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", addr)
		errCh <- srv.ListenAndServe()
	}()

	sig, stop := signal.NotifyContext(ctx, syscall.SIGTERM, os.Interrupt)
	defer stop()
	select {
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-sig.Done():
	}
	stopping.Store(true)
	drain := config.Millis("SHUTDOWN_DRAIN_MS", 5*time.Second)
	slog.Info("shutdown requested, draining", "drain", drain.String())
	time.Sleep(drain)
	c, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return srv.Shutdown(c)
}

// Counter and gauge helpers so mode packages do not import prometheus directly.

func NewCounterVec(name, help string, labels ...string) *prometheus.CounterVec {
	return promauto.NewCounterVec(prometheus.CounterOpts{Name: name, Help: help}, labels)
}

func NewGauge(name, help string) prometheus.Gauge {
	return promauto.NewGauge(prometheus.GaugeOpts{Name: name, Help: help})
}

func NewGaugeVec(name, help string, labels ...string) *prometheus.GaugeVec {
	return promauto.NewGaugeVec(prometheus.GaugeOpts{Name: name, Help: help}, labels)
}

func NewHistogram(name, help string, buckets []float64) prometheus.Histogram {
	return promauto.NewHistogram(prometheus.HistogramOpts{Name: name, Help: help, Buckets: buckets})
}
