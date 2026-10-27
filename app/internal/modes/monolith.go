package modes

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"sync/atomic"
	"time"

	"relnusa/internal/bank"
	"relnusa/internal/config"
	"relnusa/internal/httpx"
	"relnusa/internal/obs"
	"relnusa/internal/store"
	"relnusa/internal/web"
)

// Monolith runs every feature in one process with one connection pool, no
// cache, no queue and no timeout on the bank call. This is the "before"
// picture in the talk.
func Monolith(ctx context.Context) error {
	pool, err := openDB(ctx, 20)
	if err != nil {
		return err
	}
	defer pool.Close()

	bankClient := bank.New(config.Str("BANK_URL", "http://banksim.bank:8080"), config.Millis("BANK_TIMEOUT_MS", 0))
	costMs := config.Int("SEARCH_DB_COST_MS", 25)
	warmup := config.Millis("WARMUP_MS", 12*time.Second)
	started := time.Now()

	var migrated atomic.Bool
	go func() {
		store.WaitAndMigrate(ctx, pool)
		migrated.Store(true)
		t := time.NewTicker(time.Hour)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				_ = store.EnsureInventory(ctx, pool)
			}
		}
	}()

	mux := http.NewServeMux()
	web.Register(mux)
	obs.Handle(mux, "GET /api/info", "/api/info", infoHandler("legacy"))
	obs.Handle(mux, "GET /api/stations", "/api/stations", func(w http.ResponseWriter, r *http.Request) {
		st, err := store.Stations(r.Context(), pool)
		if err != nil {
			storeErr(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, st)
	})
	obs.Handle(mux, "GET /api/search", "/api/search", func(w http.ResponseWriter, r *http.Request) {
		from, to, date, err := httpx.SearchParams(r)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_request", err.Error())
			return
		}
		res, err := store.Search(r.Context(), pool, from, to, date, costMs)
		if err != nil {
			storeErr(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{"results": res, "source": "database"})
	})
	obs.Handle(mux, "POST /api/bookings", "/api/bookings", func(w http.ResponseWriter, r *http.Request) {
		req, err := httpx.ParseBooking(r)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_request", err.Error())
			return
		}
		b, err := store.BookLegacy(r.Context(), pool, req.TrainID, req.Date, req.Passenger,
			func(ctx context.Context, key string, amount int) (string, error) {
				return bankClient.Charge(ctx, key, amount)
			})
		var pe *store.PaymentError
		if errors.As(err, &pe) {
			if errors.Is(err, context.Canceled) {
				return
			}
			httpx.Error(w, http.StatusBadGateway, "payment_failed", "the bank could not process the payment, please try again")
			return
		}
		if err != nil {
			storeErr(w, err)
			return
		}
		httpx.JSON(w, http.StatusCreated, map[string]any{"booking": b, "message": "Payment successful. Your e-ticket has been issued."})
	})
	obs.Handle(mux, "GET /api/bookings/{id}", "/api/bookings/{id}", func(w http.ResponseWriter, r *http.Request) {
		b, err := store.GetBooking(r.Context(), pool, r.PathValue("id"))
		if err != nil {
			storeErr(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{"booking": b})
	})

	// Readiness only reflects startup (warm-up and first migration). Once
	// up, the pod stays "Ready" even when it is too overloaded to serve
	// anyone, which is exactly what happens to many real monoliths.
	ready := func(c context.Context) error {
		if time.Since(started) < warmup {
			return fmt.Errorf("warming up")
		}
		if !migrated.Load() {
			return fmt.Errorf("database not migrated yet")
		}
		return nil
	}
	return obs.Run(ctx, mux, ready)
}
