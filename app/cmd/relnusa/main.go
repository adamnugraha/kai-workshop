// Command relnusa runs one part of the fictional RelNusa train-booking demo.
//
//	relnusa monolith        legacy: everything in one process
//	relnusa gateway         modern: web UI, routing, virtual waiting room
//	relnusa search          modern: cached search
//	relnusa booking         modern: seat holds and payment queue
//	relnusa payment-worker  modern: charges the bank behind a circuit breaker
//	relnusa banksim         simulated external payment provider
//	relnusa reset           clear bookings and refill seats
//	relnusa migrate         create tables and seed data
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	_ "time/tzdata"

	"relnusa/internal/config"
	"relnusa/internal/modes"
	"relnusa/internal/obs"
)

func main() {
	mode := config.Str("RELNUSA_MODE", "")
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}
	runners := map[string]func(context.Context) error{
		"monolith":       modes.Monolith,
		"gateway":        modes.Gateway,
		"search":         modes.Search,
		"booking":        modes.Booking,
		"payment-worker": modes.PaymentWorker,
		"banksim":        modes.BankSim,
		"reset":          modes.Reset,
		"migrate":        modes.Migrate,
	}
	run, ok := runners[mode]
	if !ok {
		fmt.Fprintln(os.Stderr, "usage: relnusa monolith|gateway|search|booking|payment-worker|banksim|reset|migrate")
		os.Exit(2)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	obs.Setup(mode)
	shutdown := obs.InitTracing(ctx)
	err := run(ctx)
	_ = shutdown(context.Background())
	if err != nil {
		slog.Error("exiting", "err", err)
		os.Exit(1)
	}
}
