package modes

import (
	"context"
	"fmt"
	"os"
	"time"

	"relnusa/internal/store"
)

// Reset empties bookings, refills seats, and clears the cache and payment
// queue when Redis is configured. Run it between demo rounds.
func Reset(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	pool, err := openDB(ctx, 4)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := store.Migrate(ctx, pool); err != nil {
		return err
	}
	if err := store.Reset(ctx, pool); err != nil {
		return err
	}
	fmt.Println("database: bookings cleared, seats refilled")
	if os.Getenv("REDIS_ADDR") != "" {
		rdb := openRedis()
		defer rdb.Close()
		deleted := 0
		iter := rdb.Scan(ctx, 0, "*search:*", 500).Iterator()
		for iter.Next(ctx) {
			rdb.Del(ctx, iter.Val())
			deleted++
		}
		rdb.Del(ctx, "stations:v1", "stale:stations:v1", paymentStream)
		fmt.Printf("redis: %d cache keys and the payment queue cleared\n", deleted)
	}
	return nil
}

// Migrate only applies the schema and seed data.
func Migrate(ctx context.Context) error {
	pool, err := openDB(ctx, 4)
	if err != nil {
		return err
	}
	defer pool.Close()
	return store.Migrate(ctx, pool)
}
