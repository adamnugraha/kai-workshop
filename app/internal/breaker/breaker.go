// Package breaker is a small circuit breaker: after too many failures it
// stops calling a struggling dependency for a while, then lets a few trial
// calls through to see whether it has recovered.
package breaker

import (
	"sync"
	"time"
)

// State of the breaker.
type State int32

const (
	Closed   State = 0 // calls flow normally
	HalfOpen State = 1 // a few trial calls allowed
	Open     State = 2 // calls are refused immediately
)

func (s State) String() string {
	switch s {
	case Closed:
		return "closed"
	case HalfOpen:
		return "half-open"
	case Open:
		return "open"
	}
	return "unknown"
}

// Breaker tracks recent call results.
type Breaker struct {
	mu        sync.Mutex
	state     State
	results   []bool // true = failure
	pos       int
	filled    int
	minCalls  int
	threshold float64
	openFor   time.Duration
	openedAt  time.Time
	trials    int
	trialsOut int
	trialsOK  int
	onChange  func(State)
}

// New creates a breaker that opens when at least threshold of the last
// window calls failed (and at least minCalls were seen), stays open for
// openFor, then allows trials calls in half-open state.
func New(window, minCalls int, threshold float64, openFor time.Duration, trials int, onChange func(State)) *Breaker {
	if onChange == nil {
		onChange = func(State) {}
	}
	b := &Breaker{results: make([]bool, window), minCalls: minCalls, threshold: threshold, openFor: openFor, trials: trials, onChange: onChange}
	onChange(Closed)
	return b
}

// State returns the current state, moving from open to half-open when the
// open period has passed.
func (b *Breaker) State() State {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.maybeHalfOpen()
	return b.state
}

func (b *Breaker) maybeHalfOpen() {
	if b.state == Open && time.Since(b.openedAt) >= b.openFor {
		b.set(HalfOpen)
		b.trialsOut, b.trialsOK = 0, 0
	}
}

// Allow reports whether a call may go ahead now.
func (b *Breaker) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.maybeHalfOpen()
	switch b.state {
	case Closed:
		return true
	case HalfOpen:
		if b.trialsOut < b.trials {
			b.trialsOut++
			return true
		}
	}
	return false
}

// Record stores the result of a call that Allow let through.
func (b *Breaker) Record(failure bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	switch b.state {
	case HalfOpen:
		if failure {
			b.trip()
			return
		}
		b.trialsOK++
		if b.trialsOK >= b.trials {
			b.clear()
			b.set(Closed)
		}
	case Closed:
		b.results[b.pos] = failure
		b.pos = (b.pos + 1) % len(b.results)
		if b.filled < len(b.results) {
			b.filled++
		}
		if b.filled >= b.minCalls {
			fails := 0
			for i := 0; i < b.filled; i++ {
				if b.results[i] {
					fails++
				}
			}
			if float64(fails)/float64(b.filled) >= b.threshold {
				b.trip()
			}
		}
	}
}

func (b *Breaker) trip() {
	b.clear()
	b.openedAt = time.Now()
	b.set(Open)
}

func (b *Breaker) clear() {
	for i := range b.results {
		b.results[i] = false
	}
	b.pos, b.filled = 0, 0
}

func (b *Breaker) set(s State) {
	if b.state != s {
		b.state = s
		b.onChange(s)
	}
}
