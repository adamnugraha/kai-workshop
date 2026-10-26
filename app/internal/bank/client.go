// Package bank is the client for the external payment provider (simulated
// by the banksim service).
package bank

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Client calls the payment provider.
type Client struct {
	base string
	http *http.Client
}

// New creates a client. timeout 0 means "wait forever", which is what the
// legacy monolith does.
func New(base string, timeout time.Duration) *Client {
	tr := &http.Transport{
		MaxIdleConns:        512,
		MaxIdleConnsPerHost: 512,
		IdleConnTimeout:     60 * time.Second,
		DialContext:         (&net.Dialer{Timeout: 2 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
	}
	return &Client{base: base, http: &http.Client{Timeout: timeout, Transport: otelhttp.NewTransport(tr)}}
}

// ErrStatus is returned for a non-2xx answer.
var ErrStatus = errors.New("bank returned an error status")

// Charge asks the bank to take payment. The idempotency key makes retries
// safe: the bank returns the original result instead of charging twice.
func (c *Client) Charge(ctx context.Context, key string, amount int) (string, error) {
	body, _ := json.Marshal(map[string]any{"amount": amount, "reference": key})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/charge", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", key)
	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		_, _ = io.Copy(io.Discard, resp.Body)
		return "", fmt.Errorf("%w: %d", ErrStatus, resp.StatusCode)
	}
	var out struct {
		ChargeID string `json:"charge_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	return out.ChargeID, nil
}

// IsTimeout reports whether err is a timeout.
func IsTimeout(err error) bool {
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	var ne net.Error
	return errors.As(err, &ne) && ne.Timeout()
}
