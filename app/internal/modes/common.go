// Package modes contains one entry point per process type. All of them are
// compiled into a single binary and selected by the first argument.
package modes

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"

	"relnusa/internal/config"
	"relnusa/internal/httpx"
	"relnusa/internal/obs"
	"relnusa/internal/store"
)

func infoHandler(mode string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]any{
			"mode":      mode,
			"service":   obs.Service,
			"version":   obs.Version,
			"hot_train": store.HotTrain,
			"hot_date":  config.HotDate(),
			"hot_route": map[string]string{"from": "JKT", "to": "JOG"},
			"today":     config.Today().Format("2006-01-02"),
		})
	}
}

func openDB(ctx context.Context, defaultMax int) (*pgxpool.Pool, error) {
	return store.Open(ctx, config.DatabaseURL(), int32(config.Int("DB_MAX_CONNS", defaultMax)), obs.Service)
}

func openRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr:         config.Str("REDIS_ADDR", "redis:6379"),
		PoolSize:     config.Int("REDIS_POOL_SIZE", 64),
		DialTimeout:  time.Second,
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
		MaxRetries:   1,
	})
	if err := redisotel.InstrumentTracing(rdb); err != nil {
		slog.Warn("redis tracing", "err", err)
	}
	return rdb
}

// storeErr maps store and context errors to HTTP answers in Bahasa Indonesia.
func storeErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "data tidak ditemukan")
	case errors.Is(err, store.ErrSoldOut):
		httpx.Error(w, http.StatusConflict, "sold_out", "maaf, tiket untuk kereta ini sudah habis")
	case errors.Is(err, context.Canceled):
		// The caller went away; nothing useful to send.
	case errors.Is(err, context.DeadlineExceeded):
		httpx.Error(w, http.StatusGatewayTimeout, "timeout", "permintaan terlalu lama diproses")
	case errors.Is(err, errSearchDBUnavailable):
		httpx.Error(w, http.StatusServiceUnavailable, "search_unavailable", "pencarian sementara tidak tersedia, silakan coba lagi")
	default:
		slog.Error("store error", "err", err)
		httpx.Error(w, http.StatusServiceUnavailable, "unavailable", "sistem sedang sibuk, silakan coba lagi")
	}
}
