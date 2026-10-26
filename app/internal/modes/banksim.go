package modes

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"relnusa/internal/config"
	"relnusa/internal/httpx"
	"relnusa/internal/obs"
)

type bankConfig struct {
	Mode      string  `json:"mode"`
	LatencyMS int     `json:"latency_ms"`
	JitterMS  int     `json:"jitter_ms"`
	ErrorRate float64 `json:"error_rate"`
}

var bankPresets = map[string]bankConfig{
	"normal": {Mode: "normal", LatencyMS: 120, JitterMS: 40},
	"slow":   {Mode: "slow", LatencyMS: 3000, JitterMS: 500},
	"errors": {Mode: "errors", LatencyMS: 150, JitterMS: 50, ErrorRate: 0.5},
	"down":   {Mode: "down", LatencyMS: 30000, JitterMS: 0},
}

var (
	bankRequests = obs.NewCounterVec("bank_requests_total", "Charge requests at the simulated bank, by outcome.", "outcome")
	bankUnique   = obs.NewCounterVec("bank_unique_charges_total", "Distinct charges actually taken (duplicates excluded).")
	bankLatency  = obs.NewGauge("bank_configured_latency_ms", "Configured base latency of the simulated bank.")
	bankErrRate  = obs.NewGauge("bank_configured_error_rate", "Configured error rate of the simulated bank.")
)

// BankSim simulates an external payment provider whose speed and error rate
// can be changed at runtime for the demos.
func BankSim(ctx context.Context) error {
	var mu sync.RWMutex
	cfg, ok := bankPresets[config.Str("BANK_MODE", "normal")]
	if !ok {
		cfg = bankPresets["normal"]
	}
	apply := func(c bankConfig) {
		mu.Lock()
		cfg = c
		mu.Unlock()
		bankLatency.Set(float64(c.LatencyMS))
		bankErrRate.Set(c.ErrorRate)
	}
	apply(cfg)
	for _, o := range []string{"success", "error", "duplicate", "abandoned"} {
		bankRequests.WithLabelValues(o)
	}
	bankUnique.WithLabelValues()

	var charges sync.Map
	var stored atomic.Int64

	mux := http.NewServeMux()
	obs.Handle(mux, "POST /charge", "/charge", func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("Idempotency-Key")
		if key != "" {
			if v, ok := charges.Load(key); ok {
				bankRequests.WithLabelValues("duplicate").Inc()
				httpx.JSON(w, http.StatusOK, v)
				return
			}
		}
		mu.RLock()
		c := cfg
		mu.RUnlock()
		d := time.Duration(c.LatencyMS) * time.Millisecond
		if c.JitterMS > 0 {
			d += time.Duration(rand.IntN(2*c.JitterMS+1)-c.JitterMS) * time.Millisecond
		}
		select {
		case <-time.After(d):
		case <-r.Context().Done():
			bankRequests.WithLabelValues("abandoned").Inc()
			return
		}
		if c.ErrorRate > 0 && rand.Float64() < c.ErrorRate {
			bankRequests.WithLabelValues("error").Inc()
			httpx.Error(w, http.StatusServiceUnavailable, "bank_unavailable", "bank sedang mengalami gangguan")
			return
		}
		res := map[string]string{"charge_id": fmt.Sprintf("CHG-%012d", rand.Int64N(1e12)), "status": "SUCCESS"}
		if key != "" {
			if actual, loaded := charges.LoadOrStore(key, res); loaded {
				bankRequests.WithLabelValues("duplicate").Inc()
				httpx.JSON(w, http.StatusOK, actual)
				return
			}
			if stored.Add(1) > 500000 {
				charges.Clear()
				stored.Store(0)
			}
		}
		bankUnique.WithLabelValues().Inc()
		bankRequests.WithLabelValues("success").Inc()
		httpx.JSON(w, http.StatusOK, res)
	})
	mux.HandleFunc("GET /admin/config", func(w http.ResponseWriter, r *http.Request) {
		mu.RLock()
		defer mu.RUnlock()
		httpx.JSON(w, http.StatusOK, cfg)
	})
	mux.HandleFunc("PUT /admin/config", func(w http.ResponseWriter, r *http.Request) {
		if m := r.URL.Query().Get("mode"); m != "" {
			p, ok := bankPresets[m]
			if !ok {
				httpx.Error(w, http.StatusBadRequest, "bad_mode", "mode harus normal, slow, errors atau down")
				return
			}
			apply(p)
			httpx.JSON(w, http.StatusOK, p)
			return
		}
		var c bankConfig
		if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_request", err.Error())
			return
		}
		if c.Mode == "" {
			c.Mode = "custom"
		}
		apply(c)
		httpx.JSON(w, http.StatusOK, c)
	})
	return obs.Run(ctx, mux, nil)
}
