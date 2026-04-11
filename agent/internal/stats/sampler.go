// ICD360SVPN — internal/stats/sampler.go
//
// Background goroutine that polls the WireGuard interface every N
// seconds (via wgctrl, no shell-out) and persists the per-peer byte
// counter delta into the sqlite store.
//
// Counter-reset handling: WireGuard's per-peer ReceiveBytes /
// TransmitBytes counters reset to zero whenever the interface is
// recreated (wg-quick down + up, server reboot, etc.). The sampler
// detects this by comparing the current cumulative value against the
// previous sample for the same peer; if current < previous, the new
// delta is just the current value (we treat it as "started fresh").

package stats

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/wgctrl"
)

// Sampler polls a WireGuard interface and writes deltas to a Store.
type Sampler struct {
	client    *wgctrl.Client
	iface     string
	store     *Store
	period    time.Duration
	retention time.Duration

	mu       sync.Mutex
	previous map[string]Sample // pubkey -> last sample (for delta computation)
}

// NewSampler constructs a sampler. period is the poll interval (60s
// is reasonable for ~20 peers); retention is how long to keep raw
// samples before Prune() drops them.
func NewSampler(client *wgctrl.Client, iface string, store *Store, period, retention time.Duration) *Sampler {
	return &Sampler{
		client:    client,
		iface:     iface,
		store:     store,
		period:    period,
		retention: retention,
		previous:  map[string]Sample{},
	}
}

// Run blocks until ctx is cancelled. Should be called in a goroutine.
//
// On startup it seeds `previous` from the most recent sample per peer
// in the database, so a restart does not generate a phantom delta
// equal to the entire cumulative counter.
func (s *Sampler) Run(ctx context.Context) error {
	if seed, err := s.store.LatestPerPeer(ctx); err == nil {
		s.mu.Lock()
		s.previous = seed
		s.mu.Unlock()
		slog.Info("sampler seeded", "peers", len(seed))
	} else {
		slog.Warn("sampler seed failed", "err", err)
	}

	// Run an immediate first poll so the first row lands quickly,
	// then settle into the regular cadence.
	s.poll(ctx)

	pollTicker := time.NewTicker(s.period)
	defer pollTicker.Stop()

	// Prune once per day.
	pruneTicker := time.NewTicker(24 * time.Hour)
	defer pruneTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-pollTicker.C:
			s.poll(ctx)
		case <-pruneTicker.C:
			if n, err := s.store.Prune(ctx, s.retention); err != nil {
				slog.Warn("sampler prune failed", "err", err)
			} else if n > 0 {
				slog.Info("sampler pruned old samples", "rows", n)
			}
		}
	}
}

// poll reads the live WireGuard interface, computes per-peer deltas
// against the previous snapshot, and writes one Sample per peer.
func (s *Sampler) poll(ctx context.Context) {
	dev, err := s.client.Device(s.iface)
	if err != nil {
		slog.Warn("sampler poll failed", "err", err)
		return
	}
	now := time.Now().UTC()

	s.mu.Lock()
	defer s.mu.Unlock()

	for _, p := range dev.Peers {
		pub := p.PublicKey.String()
		rxNow := uint64(p.ReceiveBytes)
		txNow := uint64(p.TransmitBytes)

		var rxDelta, txDelta uint64
		if prev, ok := s.previous[pub]; ok {
			if rxNow >= prev.RxTotal {
				rxDelta = rxNow - prev.RxTotal
			} else {
				// Counter reset (interface restarted) — treat the
				// current value as the entire delta since the reset.
				rxDelta = rxNow
			}
			if txNow >= prev.TxTotal {
				txDelta = txNow - prev.TxTotal
			} else {
				txDelta = txNow
			}
		}
		// On the very first observation of a peer the deltas are
		// zero — we have nothing to compare against. The next sample
		// will record a real delta.

		sample := Sample{
			PublicKey: pub,
			Timestamp: now,
			RxTotal:   rxNow,
			TxTotal:   txNow,
			RxDelta:   rxDelta,
			TxDelta:   txDelta,
		}
		if err := s.store.Insert(ctx, sample); err != nil {
			slog.Warn("sampler insert failed", "err", err, "peer", pub)
			continue
		}
		s.previous[pub] = sample
	}
}
