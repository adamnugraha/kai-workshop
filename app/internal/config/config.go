// Package config reads settings from environment variables with defaults.
package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"time"
)

// Str returns the env var or a default.
func Str(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

// Int returns the env var as int or a default.
func Int(key string, def int) int {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

// Float returns the env var as float64 or a default.
func Float(key string, def float64) float64 {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return def
}

// Duration reads milliseconds from the env var.
func Millis(key string, def time.Duration) time.Duration {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return time.Duration(n) * time.Millisecond
		}
	}
	return def
}

// DatabaseURL builds a Postgres URL from DATABASE_URL or from DB_* parts.
// DB_HOST can be overridden (for example to point the search service at
// the read-only replicas) while user and password still come from the
// CloudNativePG secret.
func DatabaseURL() string {
	if v := os.Getenv("DATABASE_URL"); v != "" {
		return v
	}
	host := Str("DB_HOST", "localhost")
	port := Str("DB_PORT", "5432")
	user := Str("DB_USER", "relnusa")
	pass := Str("DB_PASSWORD", "relnusa")
	name := Str("DB_NAME", "relnusa")
	u := &url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(user, pass),
		Host:   fmt.Sprintf("%s:%s", host, port),
		Path:   "/" + name,
	}
	q := u.Query()
	q.Set("sslmode", Str("DB_SSLMODE", "prefer"))
	u.RawQuery = q.Encode()
	return u.String()
}

// Jakarta is the time zone used for travel dates.
var Jakarta = mustLoad("Asia/Jakarta")

func mustLoad(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		return time.FixedZone("WIB", 7*3600)
	}
	return loc
}

// Today returns today's date in Jakarta as YYYY-MM-DD.
func Today() time.Time {
	now := time.Now().In(Jakarta)
	return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, Jakarta)
}

// HotDate is the travel date used for the ticket-rush demo.
func HotDate() string {
	return Today().AddDate(0, 0, Int("HOT_DATE_OFFSET_DAYS", 3)).Format("2006-01-02")
}
