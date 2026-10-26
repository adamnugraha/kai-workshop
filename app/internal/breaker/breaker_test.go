package breaker

import (
	"testing"
	"time"
)

func TestOpensAfterFailuresAndRecovers(t *testing.T) {
	var states []State
	b := New(10, 5, 0.5, 50*time.Millisecond, 2, func(s State) { states = append(states, s) })

	// Four failures are below the minimum number of calls: still closed.
	for i := 0; i < 4; i++ {
		if !b.Allow() {
			t.Fatalf("call %d refused while closed", i)
		}
		b.Record(true)
	}
	if got := b.State(); got != Closed {
		t.Fatalf("state after 4 failures = %v, want closed", got)
	}

	// The fifth failure reaches the minimum with 100% failures: open.
	b.Allow()
	b.Record(true)
	if got := b.State(); got != Open {
		t.Fatalf("state after 5 failures = %v, want open", got)
	}
	if b.Allow() {
		t.Fatal("call allowed while open")
	}

	// After the open period, two trial calls are allowed, a third is not.
	time.Sleep(60 * time.Millisecond)
	if !b.Allow() || !b.Allow() {
		t.Fatal("trial calls refused in half-open state")
	}
	if b.Allow() {
		t.Fatal("more trial calls allowed than configured")
	}

	// Both trials succeed: closed again.
	b.Record(false)
	b.Record(false)
	if got := b.State(); got != Closed {
		t.Fatalf("state after successful trials = %v, want closed", got)
	}

	want := []State{Closed, Open, HalfOpen, Closed}
	if len(states) != len(want) {
		t.Fatalf("state changes = %v, want %v", states, want)
	}
	for i := range want {
		if states[i] != want[i] {
			t.Fatalf("state changes = %v, want %v", states, want)
		}
	}
}

func TestFailedTrialReopens(t *testing.T) {
	b := New(10, 2, 0.5, 20*time.Millisecond, 1, nil)
	for i := 0; i < 2; i++ {
		b.Allow()
		b.Record(true)
	}
	time.Sleep(30 * time.Millisecond)
	if !b.Allow() {
		t.Fatal("trial refused")
	}
	b.Record(true)
	if got := b.State(); got != Open {
		t.Fatalf("state after failed trial = %v, want open", got)
	}
}

func TestMostlySuccessfulStaysClosed(t *testing.T) {
	b := New(10, 5, 0.5, time.Second, 1, nil)
	for i := 0; i < 20; i++ {
		b.Allow()
		b.Record(i%4 == 0) // 25% failures
	}
	if got := b.State(); got != Closed {
		t.Fatalf("state with 25%% failures = %v, want closed", got)
	}
}
