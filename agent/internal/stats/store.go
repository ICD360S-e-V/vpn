// Package stats persists per-peer WireGuard byte counters over time
// and answers historical bandwidth queries.
//
// Storage backend: sqlite via modernc.org/sqlite (pure Go, no CGo —
// keeps the agent statically linkable). Schema is intentionally
// minimal: one row per (pubkey, sample_time), holding both the
// cumulative running totals AND the deltas computed against the
// previous sample for that peer. The deltas are what charts query;
// the totals are kept for debuggability and counter-reset detection.
//
// Retention: the sampler asks Prune() once per day to drop samples
// older than the configured retention. There are no rollups in M4.4
// — the table is small enough at 20 peers × 1440 samples/day × 90
// days ≈ 2.6 M rows.
package stats

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

// Sample is one row of the samples table.
type Sample struct {
	PublicKey string
	Timestamp time.Time
	RxTotal   uint64
	TxTotal   uint64
	RxDelta   uint64
	TxDelta   uint64
}

// Series is what the API returns for a single peer over a window.
// Granularity bucketing is done in Go after pulling the raw rows.
type Series struct {
	PublicKey   string  `json:"public_key"`
	Granularity string  `json:"granularity"`
	Points      []Point `json:"points"`
}

// Point is one bucket in a Series.
type Point struct {
	T  time.Time `json:"t"`
	Rx uint64    `json:"rx"`
	Tx uint64    `json:"tx"`
}

// Store wraps the sqlite handle and the prepared statements.
type Store struct {
	db *sql.DB
}

// Open opens (or creates) a sqlite database at path and runs the
// schema migration. Caller must Close().
func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=foreign_keys(ON)")
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	// modernc.org/sqlite is single-process anyway; cap at 1 to avoid
	// "database is locked" surprises under busy timeouts.
	db.SetMaxOpenConns(1)

	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	return &Store{db: db}, nil
}

// Close releases the database handle.
func (s *Store) Close() error {
	if s.db == nil {
		return nil
	}
	err := s.db.Close()
	s.db = nil
	return err
}

const schema = `
CREATE TABLE IF NOT EXISTS samples (
	pubkey   TEXT    NOT NULL,
	ts       INTEGER NOT NULL,        -- unix epoch seconds, UTC
	rx_total INTEGER NOT NULL,        -- cumulative wgctrl ReceiveBytes
	tx_total INTEGER NOT NULL,        -- cumulative wgctrl TransmitBytes
	rx_delta INTEGER NOT NULL,        -- bytes received since previous sample
	tx_delta INTEGER NOT NULL,        -- bytes sent since previous sample
	PRIMARY KEY (pubkey, ts)
);

CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts);
`

// Insert appends a single sample. Caller is responsible for computing
// deltas (the sampler does so against an in-memory cache).
func (s *Store) Insert(ctx context.Context, sample Sample) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT OR REPLACE INTO samples
		(pubkey, ts, rx_total, tx_total, rx_delta, tx_delta)
		VALUES (?, ?, ?, ?, ?, ?)`,
		sample.PublicKey,
		sample.Timestamp.UTC().Unix(),
		sample.RxTotal, sample.TxTotal,
		sample.RxDelta, sample.TxDelta,
	)
	return err
}

// LatestPerPeer returns the most recent (rx_total, tx_total) seen for
// each peer in the table, used to seed the sampler's in-memory state
// when the agent restarts. Without it the first sample after a
// restart would record a huge phantom delta equal to the cumulative
// total since interface bring-up.
func (s *Store) LatestPerPeer(ctx context.Context) (map[string]Sample, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT pubkey, ts, rx_total, tx_total, rx_delta, tx_delta
		FROM samples
		WHERE (pubkey, ts) IN (
			SELECT pubkey, MAX(ts) FROM samples GROUP BY pubkey
		)
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := map[string]Sample{}
	for rows.Next() {
		var s Sample
		var ts int64
		if err := rows.Scan(&s.PublicKey, &ts, &s.RxTotal, &s.TxTotal, &s.RxDelta, &s.TxDelta); err != nil {
			return nil, err
		}
		s.Timestamp = time.Unix(ts, 0).UTC()
		out[s.PublicKey] = s
	}
	return out, rows.Err()
}

// Query returns a Series for one peer, bucketed at the requested
// granularity, between from and to (inclusive of from, exclusive of to).
//
// Granularities supported: "minute", "hour", "day". Anything else is
// treated as "day".
func (s *Store) Query(ctx context.Context, pubkey string, from, to time.Time, granularity string) (*Series, error) {
	if from.After(to) {
		return nil, errors.New("from must be <= to")
	}

	bucketSeconds := bucketSize(granularity)
	rows, err := s.db.QueryContext(ctx, `
		SELECT
			(ts / ?) * ?  AS bucket_ts,
			SUM(rx_delta) AS rx,
			SUM(tx_delta) AS tx
		FROM samples
		WHERE pubkey = ? AND ts >= ? AND ts < ?
		GROUP BY bucket_ts
		ORDER BY bucket_ts
	`, bucketSeconds, bucketSeconds, pubkey, from.UTC().Unix(), to.UTC().Unix())
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	series := &Series{
		PublicKey:   pubkey,
		Granularity: granularityCanonical(granularity),
	}
	for rows.Next() {
		var bucketTs int64
		var rx, tx uint64
		if err := rows.Scan(&bucketTs, &rx, &tx); err != nil {
			return nil, err
		}
		series.Points = append(series.Points, Point{
			T:  time.Unix(bucketTs, 0).UTC(),
			Rx: rx,
			Tx: tx,
		})
	}
	return series, rows.Err()
}

// Prune deletes samples older than `keep`. Called periodically by the
// sampler.
func (s *Store) Prune(ctx context.Context, keep time.Duration) (int64, error) {
	cutoff := time.Now().Add(-keep).UTC().Unix()
	res, err := s.db.ExecContext(ctx, `DELETE FROM samples WHERE ts < ?`, cutoff)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

func bucketSize(granularity string) int64 {
	switch granularity {
	case "minute":
		return 60
	case "hour":
		return 3600
	case "day", "":
		return 86400
	default:
		return 86400
	}
}

func granularityCanonical(g string) string {
	switch g {
	case "minute", "hour", "day":
		return g
	default:
		return "day"
	}
}
