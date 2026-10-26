// Package store holds the database schema, seed data and queries for the
// fictional RelNusa booking system. The same tables back both the legacy
// monolith and the modern services; only the way they are used differs.
package store

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/exaring/otelpgx"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"relnusa/internal/config"
)

var (
	ErrNotFound = errors.New("not found")
	ErrSoldOut  = errors.New("sold out")
)

// PaymentError wraps a failed charge in the legacy flow.
type PaymentError struct{ Err error }

func (e *PaymentError) Error() string { return "payment failed: " + e.Err.Error() }
func (e *PaymentError) Unwrap() error { return e.Err }

// Open creates a connection pool with tracing on every query.
func Open(ctx context.Context, dsn string, maxConns int32, appName string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = maxConns
	cfg.MinConns = 1
	cfg.HealthCheckPeriod = 5 * time.Second
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.ConnConfig.ConnectTimeout = 3 * time.Second
	cfg.ConnConfig.RuntimeParams["timezone"] = "Asia/Jakarta"
	cfg.ConnConfig.RuntimeParams["application_name"] = appName
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
	return pgxpool.NewWithConfig(ctx, cfg)
}

// WaitAndMigrate retries until the database answers, then migrates.
func WaitAndMigrate(ctx context.Context, pool *pgxpool.Pool) {
	for attempt := 1; ; attempt++ {
		err := Migrate(ctx, pool)
		if err == nil {
			return
		}
		if ctx.Err() != nil {
			return
		}
		slog.Warn("database not ready, retrying migration", "attempt", attempt, "err", err)
		time.Sleep(3 * time.Second)
	}
}

const schema = `
CREATE TABLE IF NOT EXISTS stations (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS trains (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  origin TEXT NOT NULL REFERENCES stations(code),
  destination TEXT NOT NULL REFERENCES stations(code),
  depart TEXT NOT NULL,
  arrive TEXT NOT NULL,
  class TEXT NOT NULL,
  price INT NOT NULL
);
CREATE TABLE IF NOT EXISTS inventory (
  train_id TEXT NOT NULL REFERENCES trains(id),
  travel_date DATE NOT NULL,
  capacity INT NOT NULL,
  available INT NOT NULL CHECK (available >= 0),
  PRIMARY KEY (train_id, travel_date)
);
CREATE TABLE IF NOT EXISTS bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  train_id TEXT NOT NULL,
  travel_date DATE NOT NULL,
  passenger TEXT NOT NULL,
  status TEXT NOT NULL,
  amount INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  hold_expires_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  ticket_code TEXT,
  idempotency_key TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS bookings_status_hold ON bookings (status, hold_expires_at);
`

type seedTrain struct {
	id, name, from, to, depart, arrive, class string
	price                                     int
}

var seedStations = [][2]string{
	{"JKT", "Jakarta"}, {"BDG", "Bandung"}, {"CBN", "Cirebon"}, {"SMG", "Semarang"},
	{"JOG", "Yogyakarta"}, {"SOC", "Solo"}, {"SUB", "Surabaya"}, {"MLG", "Malang"},
}

// Train names are invented for this demo.
var seedTrains = []seedTrain{
	{"RN7", "Mudik Ekspres", "JKT", "JOG", "07:00", "14:10", "Eksekutif", 520000},
	{"RN8", "Mudik Ekspres", "JOG", "JKT", "15:00", "22:10", "Eksekutif", 520000},
	{"RN11", "Kenari Malam", "JKT", "JOG", "20:00", "03:30", "Bisnis", 380000},
	{"RN12", "Kenari Malam", "JOG", "JKT", "19:30", "03:00", "Bisnis", 380000},
	{"RN15", "Cendana Pagi", "JKT", "JOG", "09:30", "17:40", "Ekonomi", 230000},
	{"RN16", "Cendana Pagi", "JOG", "JKT", "08:00", "16:10", "Ekonomi", 230000},
	{"RN101", "Melati Kilat", "JKT", "BDG", "06:00", "08:50", "Eksekutif", 250000},
	{"RN102", "Melati Kilat", "BDG", "JKT", "09:30", "12:20", "Eksekutif", 250000},
	{"RN105", "Melati Senja", "JKT", "BDG", "16:00", "18:50", "Ekonomi", 120000},
	{"RN106", "Melati Senja", "BDG", "JKT", "17:00", "19:50", "Ekonomi", 120000},
	{"RN21", "Elang Pantura", "JKT", "SUB", "08:00", "16:30", "Eksekutif", 600000},
	{"RN22", "Elang Pantura", "SUB", "JKT", "08:30", "17:00", "Eksekutif", 600000},
	{"RN23", "Rusa Malam", "JKT", "SUB", "19:00", "04:00", "Bisnis", 450000},
	{"RN24", "Rusa Malam", "SUB", "JKT", "18:30", "03:30", "Bisnis", 450000},
	{"RN31", "Kenanga Ekspres", "JKT", "SMG", "06:30", "12:10", "Eksekutif", 400000},
	{"RN32", "Kenanga Ekspres", "SMG", "JKT", "13:30", "19:10", "Eksekutif", 400000},
	{"RN41", "Kenari Siang", "BDG", "JOG", "08:00", "15:00", "Bisnis", 300000},
	{"RN42", "Kenari Siang", "JOG", "BDG", "08:30", "15:30", "Bisnis", 300000},
	{"RN51", "Kancil Timur", "JOG", "SUB", "06:00", "10:30", "Ekonomi", 150000},
	{"RN52", "Kancil Timur", "SUB", "JOG", "11:30", "16:00", "Ekonomi", 150000},
	{"RN61", "Teratai Lokal", "SUB", "MLG", "07:00", "09:30", "Ekonomi", 50000},
	{"RN62", "Teratai Lokal", "MLG", "SUB", "10:00", "12:30", "Ekonomi", 50000},
	{"RN71", "Camar Pagi", "JKT", "CBN", "06:15", "09:20", "Bisnis", 180000},
	{"RN72", "Camar Pagi", "CBN", "JKT", "10:00", "13:05", "Bisnis", 180000},
	{"RN91", "Cempaka Komuter", "JOG", "SOC", "05:30", "06:40", "Ekonomi", 20000},
	{"RN92", "Cempaka Komuter", "SOC", "JOG", "07:00", "08:10", "Ekonomi", 20000},
}

// HotTrain is the train used for the ticket-rush demo.
const HotTrain = "RN7"

// Migrate creates tables, seeds reference data once and makes sure seat
// inventory exists for the coming two weeks. Safe to run from many pods.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, "SELECT pg_advisory_lock(424242)"); err != nil {
		return err
	}
	defer func() { _, _ = conn.Exec(context.Background(), "SELECT pg_advisory_unlock(424242)") }()
	if _, err := conn.Exec(ctx, schema); err != nil {
		return fmt.Errorf("schema: %w", err)
	}
	var n int
	if err := conn.QueryRow(ctx, "SELECT count(*) FROM stations").Scan(&n); err != nil {
		return err
	}
	if n == 0 {
		batch := &pgx.Batch{}
		for _, s := range seedStations {
			batch.Queue("INSERT INTO stations (code, name) VALUES ($1, $2) ON CONFLICT DO NOTHING", s[0], s[1])
		}
		for _, t := range seedTrains {
			batch.Queue(`INSERT INTO trains (id, name, origin, destination, depart, arrive, class, price)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT DO NOTHING`,
				t.id, t.name, t.from, t.to, t.depart, t.arrive, t.class, t.price)
		}
		if err := conn.SendBatch(ctx, batch).Close(); err != nil {
			return fmt.Errorf("seed: %w", err)
		}
		slog.Info("seeded reference data", "stations", len(seedStations), "trains", len(seedTrains))
	}
	return ensureInventory(ctx, conn.Conn())
}

// EnsureInventory adds seat inventory for any missing dates.
func EnsureInventory(ctx context.Context, pool *pgxpool.Pool) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	return ensureInventory(ctx, conn.Conn())
}

func ensureInventory(ctx context.Context, conn *pgx.Conn) error {
	capacity := config.Int("SEAT_CAPACITY", 400)
	hot := config.Int("HOT_CAPACITY", 3000)
	_, err := conn.Exec(ctx, `
		INSERT INTO inventory (train_id, travel_date, capacity, available)
		SELECT t.id, d::date,
		       CASE WHEN t.id = $1::text THEN $2::int ELSE $3::int END,
		       CASE WHEN t.id = $1::text THEN $2::int ELSE $3::int END
		FROM trains t, generate_series(CURRENT_DATE - 1, CURRENT_DATE + 14, interval '1 day') d
		ON CONFLICT DO NOTHING`, HotTrain, hot, capacity)
	return err
}

// Station is a stop on the network.
type Station struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

// Train is a search result row.
type Train struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Origin      string `json:"origin"`
	Destination string `json:"destination"`
	Depart      string `json:"depart"`
	Arrive      string `json:"arrive"`
	Class       string `json:"class"`
	Price       int    `json:"price"`
	Available   int    `json:"available"`
}

// Booking is a reservation.
type Booking struct {
	ID            string     `json:"id"`
	TrainID       string     `json:"train_id"`
	TrainName     string     `json:"train_name,omitempty"`
	Date          string     `json:"date"`
	Passenger     string     `json:"passenger"`
	Status        string     `json:"status"`
	Amount        int        `json:"amount"`
	TicketCode    string     `json:"ticket_code,omitempty"`
	HoldExpiresAt *time.Time `json:"hold_expires_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
}

// Stations lists all stations.
func Stations(ctx context.Context, pool *pgxpool.Pool) ([]Station, error) {
	rows, err := pool.Query(ctx, "SELECT code, name FROM stations ORDER BY name")
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Station, error) {
		var s Station
		err := r.Scan(&s.Code, &s.Name)
		return s, err
	})
}

// Search returns trains for a route and date. costMs simulates an
// expensive query (joins, availability rules) by holding the connection.
func Search(ctx context.Context, pool *pgxpool.Pool, from, to, date string, costMs int) ([]Train, error) {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return nil, err
	}
	defer conn.Release()
	if costMs > 0 {
		if _, err := conn.Exec(ctx, "SELECT pg_sleep($1)", float64(costMs)/1000.0); err != nil {
			return nil, err
		}
	}
	rows, err := conn.Query(ctx, `
		SELECT t.id, t.name, t.origin, t.destination, t.depart, t.arrive, t.class, t.price, i.available
		FROM trains t JOIN inventory i ON i.train_id = t.id
		WHERE t.origin = $1 AND t.destination = $2 AND i.travel_date = $3::date
		ORDER BY t.depart`, from, to, date)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Train, error) {
		var t Train
		err := r.Scan(&t.ID, &t.Name, &t.Origin, &t.Destination, &t.Depart, &t.Arrive, &t.Class, &t.Price, &t.Available)
		return t, err
	})
}

// TicketCode derives a short, stable e-ticket code from a booking id.
func TicketCode(id string) string {
	sum := sha1.Sum([]byte(id))
	return "RN-" + strings.ToUpper(hex.EncodeToString(sum[:])[:8])
}

// ChargeFunc charges a passenger and returns the bank's charge id.
type ChargeFunc func(ctx context.Context, idempotencyKey string, amount int) (string, error)

// BookLegacy is the classic "lock the seat row, call the bank, then commit"
// flow. It is correct, but the row lock and the database connection are
// held for the whole bank call, so a slow bank or a rush of buyers for one
// train exhausts the connection pool and stalls every other page too.
func BookLegacy(ctx context.Context, pool *pgxpool.Pool, trainID, date, passenger string, charge ChargeFunc) (Booking, error) {
	var b Booking
	tx, err := pool.Begin(ctx)
	if err != nil {
		return b, err
	}
	defer func() { _ = tx.Rollback(context.Background()) }()

	var available, price int
	var trainName string
	err = tx.QueryRow(ctx, `
		SELECT i.available, t.price, t.name
		FROM inventory i JOIN trains t ON t.id = i.train_id
		WHERE i.train_id = $1 AND i.travel_date = $2::date
		FOR UPDATE OF i`, trainID, date).Scan(&available, &price, &trainName)
	if errors.Is(err, pgx.ErrNoRows) {
		return b, ErrNotFound
	}
	if err != nil {
		return b, err
	}
	if available <= 0 {
		return b, ErrSoldOut
	}
	id := uuid.NewString()
	if _, err := charge(ctx, id, price); err != nil {
		return b, &PaymentError{Err: err}
	}
	if _, err := tx.Exec(ctx, `UPDATE inventory SET available = available - 1 WHERE train_id = $1 AND travel_date = $2::date`, trainID, date); err != nil {
		return b, err
	}
	ticket := TicketCode(id)
	err = tx.QueryRow(ctx, `
		INSERT INTO bookings (id, train_id, travel_date, passenger, status, amount, paid_at, ticket_code)
		VALUES ($1, $2, $3::date, $4, 'PAID', $5, now(), $6)
		RETURNING created_at`, id, trainID, date, passenger, price, ticket).Scan(&b.CreatedAt)
	if err != nil {
		return b, err
	}
	if err := tx.Commit(ctx); err != nil {
		return b, err
	}
	b = Booking{ID: id, TrainID: trainID, TrainName: trainName, Date: date, Passenger: passenger,
		Status: "PAID", Amount: price, TicketCode: ticket, CreatedAt: b.CreatedAt}
	return b, nil
}

// Hold reserves a seat with one short transaction and returns a HELD
// booking. Payment happens later, outside the transaction. If the same
// idempotency key is sent again the existing booking is returned and no
// second seat is taken.
func Hold(ctx context.Context, pool *pgxpool.Pool, trainID, date, passenger, idemKey string, holdFor time.Duration) (Booking, bool, error) {
	if idemKey != "" {
		if b, err := byIdempotencyKey(ctx, pool, idemKey); err == nil {
			return b, true, nil
		} else if !errors.Is(err, ErrNotFound) {
			return Booking{}, false, err
		}
	}
	// One statement: take a seat and record the hold together. The row lock
	// on the train's inventory is held for a single round trip and released
	// at the implicit commit, so a rush on one popular train does not queue
	// up behind multi-statement transactions.
	b := Booking{TrainID: trainID, Date: date, Passenger: passenger, Status: "HELD"}
	var expires time.Time
	err := pool.QueryRow(ctx, `
		WITH seat AS (
		  UPDATE inventory i SET available = i.available - 1
		  FROM trains t
		  WHERE t.id = i.train_id AND i.train_id = $1 AND i.travel_date = $2::date AND i.available > 0
		  RETURNING t.price
		)
		INSERT INTO bookings (train_id, travel_date, passenger, status, amount, hold_expires_at, idempotency_key)
		SELECT $1, $2::date, $3, 'HELD', seat.price, now() + make_interval(secs => $4::double precision), NULLIF($5, '')
		FROM seat
		RETURNING id::text, amount, created_at, hold_expires_at`,
		trainID, date, passenger, holdFor.Seconds(), idemKey).Scan(&b.ID, &b.Amount, &b.CreatedAt, &expires)
	if errors.Is(err, pgx.ErrNoRows) {
		var exists bool
		if err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM inventory WHERE train_id = $1 AND travel_date = $2::date)`, trainID, date).Scan(&exists); err != nil {
			return Booking{}, false, err
		}
		if !exists {
			return Booking{}, false, ErrNotFound
		}
		return Booking{}, false, ErrSoldOut
	}
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" && idemKey != "" {
			// Same request arrived twice at the same moment; the statement
			// rolled back as a whole, so no extra seat was taken.
			existing, e := byIdempotencyKey(ctx, pool, idemKey)
			return existing, true, e
		}
		return Booking{}, false, err
	}
	_ = pool.QueryRow(ctx, `SELECT name FROM trains WHERE id = $1`, trainID).Scan(&b.TrainName)
	b.HoldExpiresAt = &expires
	return b, false, nil
}

func byIdempotencyKey(ctx context.Context, pool *pgxpool.Pool, key string) (Booking, error) {
	return scanBooking(pool.QueryRow(ctx, bookingSelect+` WHERE b.idempotency_key = $1`, key))
}

const bookingSelect = `
	SELECT b.id::text, b.train_id, COALESCE(t.name, ''), to_char(b.travel_date, 'YYYY-MM-DD'), b.passenger,
	       b.status, b.amount, COALESCE(b.ticket_code, ''), b.hold_expires_at, b.created_at
	FROM bookings b LEFT JOIN trains t ON t.id = b.train_id`

func scanBooking(row pgx.Row) (Booking, error) {
	var b Booking
	err := row.Scan(&b.ID, &b.TrainID, &b.TrainName, &b.Date, &b.Passenger, &b.Status, &b.Amount, &b.TicketCode, &b.HoldExpiresAt, &b.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return b, ErrNotFound
	}
	if b.Status != "HELD" {
		b.HoldExpiresAt = nil
	}
	return b, err
}

// GetBooking loads one booking.
func GetBooking(ctx context.Context, pool *pgxpool.Pool, id string) (Booking, error) {
	if _, err := uuid.Parse(id); err != nil {
		return Booking{}, ErrNotFound
	}
	return scanBooking(pool.QueryRow(ctx, bookingSelect+` WHERE b.id = $1::uuid`, id))
}

// PaymentInfo returns status and amount for the payment worker.
func PaymentInfo(ctx context.Context, pool *pgxpool.Pool, id string) (string, int, error) {
	var status string
	var amount int
	err := pool.QueryRow(ctx, `SELECT status, amount FROM bookings WHERE id = $1::uuid`, id).Scan(&status, &amount)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", 0, ErrNotFound
	}
	return status, amount, err
}

// MarkPaid moves a HELD booking to PAID. It returns false when the booking
// was no longer HELD (already paid, or expired).
func MarkPaid(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	tag, err := pool.Exec(ctx, `
		UPDATE bookings SET status = 'PAID', paid_at = now(), ticket_code = $2
		WHERE id = $1::uuid AND status = 'HELD'`, id, TicketCode(id))
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// ExpireHolds releases seats whose payment window has passed.
func ExpireHolds(ctx context.Context, pool *pgxpool.Pool) (int64, error) {
	var released int64
	err := pool.QueryRow(ctx, `
		WITH expired AS (
		  UPDATE bookings SET status = 'EXPIRED'
		  WHERE status = 'HELD' AND hold_expires_at < now()
		  RETURNING train_id, travel_date
		), grouped AS (
		  SELECT train_id, travel_date, count(*) AS n FROM expired GROUP BY 1, 2
		), upd AS (
		  UPDATE inventory i SET available = i.available + g.n
		  FROM grouped g WHERE i.train_id = g.train_id AND i.travel_date = g.travel_date
		  RETURNING g.n
		)
		SELECT COALESCE(sum(n), 0)::bigint FROM upd`).Scan(&released)
	return released, err
}

// Reset clears bookings and refills all seats. Used between demo runs.
func Reset(ctx context.Context, pool *pgxpool.Pool) error {
	if _, err := pool.Exec(ctx, `TRUNCATE bookings`); err != nil {
		return err
	}
	if _, err := pool.Exec(ctx, `UPDATE inventory SET available = capacity`); err != nil {
		return err
	}
	return EnsureInventory(ctx, pool)
}
