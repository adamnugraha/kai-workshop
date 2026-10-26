package modes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/redis/go-redis/v9"
	"golang.org/x/sync/singleflight"

	"relnusa/internal/breaker"
	"relnusa/internal/config"
	"relnusa/internal/httpx"
	"relnusa/internal/obs"
	"relnusa/internal/store"
)

var (
	searchCache   = obs.NewCounterVec("search_cache_requests_total", "Search requests by where the answer came from.", "source")
	searchBreaker = obs.NewGauge("search_db_circuit_state", "Search database circuit breaker: 0 closed, 1 half-open, 2 open.")

	errSearchDBUnavailable = errors.New("search database unavailable")
)

// Search answers schedule and seat searches from Redis first, the read
// replicas second, and a stale copy as a last resort when the database is
// unreachable (for example during a failover). A circuit breaker on the
// database path means that, once the replicas stop answering, passengers get
// the stale copy at once instead of waiting for a timeout on every search.
func Search(ctx context.Context) error {
	pool, err := openDB(ctx, 20)
	if err != nil {
		return err
	}
	defer pool.Close()
	rdb := openRedis()
	defer rdb.Close()

	costMs := config.Int("SEARCH_DB_COST_MS", 25)
	ttl := config.Millis("CACHE_TTL_MS", 5*time.Second)
	dbTimeout := config.Millis("SEARCH_DB_TIMEOUT_MS", time.Second)
	const staleTTL = 30 * time.Minute
	var group singleflight.Group
	for _, s := range []string{"cache", "database", "stale-cache"} {
		searchCache.WithLabelValues(s)
	}
	br := breaker.New(20, 5, 0.5, config.Millis("SEARCH_BREAKER_OPEN_MS", 3*time.Second), 1, func(s breaker.State) {
		searchBreaker.Set(float64(s))
		slog.Warn("search database circuit breaker changed state", "state", s.String())
	})

	stale := func(c context.Context, key string, cause error) ([]byte, string, error) {
		if b, e := rdb.Get(c, "stale:"+key).Bytes(); e == nil {
			return b, "stale-cache", nil
		}
		return nil, "", cause
	}

	load := func(r *http.Request, key string, fresh time.Duration, fetch func(context.Context) (any, error)) ([]byte, string, error) {
		if b, err := rdb.Get(r.Context(), key).Bytes(); err == nil {
			return b, "cache", nil
		}
		if !br.Allow() {
			return stale(r.Context(), key, errSearchDBUnavailable)
		}
		v, err, _ := group.Do(key, func() (any, error) {
			c, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), dbTimeout)
			defer cancel()
			res, err := fetch(c)
			if err != nil {
				return nil, err
			}
			b, err := json.Marshal(res)
			if err != nil {
				return nil, err
			}
			pipe := rdb.Pipeline()
			pipe.Set(c, key, b, fresh)
			pipe.Set(c, "stale:"+key, b, staleTTL)
			_, _ = pipe.Exec(c)
			return b, nil
		})
		// A "not found" answer means the database is fine.
		br.Record(err != nil && !errors.Is(err, store.ErrNotFound))
		if err == nil {
			return v.([]byte), "database", nil
		}
		if errors.Is(err, store.ErrNotFound) {
			return nil, "", err
		}
		return stale(r.Context(), key, err)
	}

	mux := http.NewServeMux()
	obs.Handle(mux, "GET /api/info", "/api/info", infoHandler("modern"))
	obs.Handle(mux, "GET /api/stations", "/api/stations", func(w http.ResponseWriter, r *http.Request) {
		b, src, err := load(r, "stations:v1", 5*time.Minute, func(c context.Context) (any, error) {
			return store.Stations(c, pool)
		})
		if err != nil {
			storeErr(w, err)
			return
		}
		w.Header().Set("X-Cache", src)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_, _ = w.Write(b)
	})
	obs.Handle(mux, "GET /api/search", "/api/search", func(w http.ResponseWriter, r *http.Request) {
		from, to, date, err := httpx.SearchParams(r)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_request", err.Error())
			return
		}
		key := fmt.Sprintf("search:v1:%s:%s:%s", from, to, date)
		b, src, err := load(r, key, ttl, func(c context.Context) (any, error) {
			return store.Search(c, pool, from, to, date, costMs)
		})
		if err != nil {
			storeErr(w, err)
			return
		}
		searchCache.WithLabelValues(src).Inc()
		w.Header().Set("X-Cache", src)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = fmt.Fprintf(w, `{"results":%s,"source":%q}`, b, src)
	})

	ready := func(c context.Context) error {
		if err := rdb.Ping(c).Err(); err == nil {
			return nil
		}
		return pool.Ping(c)
	}
	_ = redis.Nil
	return obs.Run(ctx, mux, ready)
}
