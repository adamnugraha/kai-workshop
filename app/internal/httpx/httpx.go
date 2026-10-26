// Package httpx holds small HTTP helpers shared by the services.
package httpx

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// JSON writes v as JSON with the given status.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// Error writes {"error": msg, "code": code}.
func Error(w http.ResponseWriter, status int, code, msg string) {
	JSON(w, status, map[string]string{"error": msg, "code": code})
}

// BookingRequest is the body of POST /api/bookings.
type BookingRequest struct {
	TrainID   string `json:"train_id"`
	Date      string `json:"date"`
	Passenger string `json:"passenger"`
}

var (
	trainRe = regexp.MustCompile(`^[A-Z0-9]{2,8}$`)
	codeRe  = regexp.MustCompile(`^[A-Z]{3}$`)
)

// ParseBooking reads and validates a booking request.
func ParseBooking(r *http.Request) (BookingRequest, error) {
	var req BookingRequest
	body, err := io.ReadAll(io.LimitReader(r.Body, 8<<10))
	if err != nil {
		return req, err
	}
	if err := json.Unmarshal(body, &req); err != nil {
		return req, errors.New("body must be JSON")
	}
	req.TrainID = strings.ToUpper(strings.TrimSpace(req.TrainID))
	req.Passenger = strings.TrimSpace(req.Passenger)
	if !trainRe.MatchString(req.TrainID) {
		return req, errors.New("train_id tidak valid")
	}
	if _, err := time.Parse("2006-01-02", req.Date); err != nil {
		return req, errors.New("date harus berformat YYYY-MM-DD")
	}
	if req.Passenger == "" {
		req.Passenger = "Penumpang"
	}
	if len(req.Passenger) > 60 {
		req.Passenger = req.Passenger[:60]
	}
	return req, nil
}

// SearchParams validates from, to and date query parameters.
func SearchParams(r *http.Request) (from, to, date string, err error) {
	q := r.URL.Query()
	from = strings.ToUpper(q.Get("from"))
	to = strings.ToUpper(q.Get("to"))
	date = q.Get("date")
	if !codeRe.MatchString(from) || !codeRe.MatchString(to) {
		return "", "", "", errors.New("kode stasiun tidak valid")
	}
	if _, e := time.Parse("2006-01-02", date); e != nil {
		return "", "", "", errors.New("date harus berformat YYYY-MM-DD")
	}
	return from, to, date, nil
}
