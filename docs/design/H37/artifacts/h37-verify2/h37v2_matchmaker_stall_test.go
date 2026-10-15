package server

// H37 phase 2b probe (agent h37-verify2), not part of Nakama. It runs in
// a clone of Nakama v3.25.0 (the version infra/remote/nakama runs) under
// hopnbop/.claude/probes/H37/h37-verify2/nakama-src/. The snoringcat
// runtime allocates a game server synchronously inside its
// MatchmakerMatched hook. This test stands a slow hook in for that
// allocation and asks: while one matched set's hook runs, does a second,
// unrelated pair that queues meanwhile get matched?

import (
	"context"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gofrs/uuid/v5"
	"github.com/heroiclabs/nakama-common/rtapi"
)

func h37v2Run(t *testing.T, hold time.Duration) (firstHook, secondQueued, secondHook, firstEnv, secondEnv time.Duration) {
	logger := loggerForTest(t)
	var mu sync.Mutex
	envAt := map[string]time.Time{}
	hookAt := map[string]time.Time{}
	start := time.Now()

	mm, cleanup, err := createTestMatchmaker(t, logger, true,
		func(presences []*PresenceID, envelope *rtapi.Envelope) {
			m := envelope.GetMatchmakerMatched()
			if m == nil {
				return
			}
			mu.Lock()
			envAt[m.GetSelf().GetPresence().GetUserId()] = time.Now()
			mu.Unlock()
		})
	if err != nil {
		t.Fatalf("createTestMatchmaker: %v", err)
	}
	defer cleanup()

	mm.runtime.matchmakerMatchedFunction = func(
		ctx context.Context, entries []*MatchmakerEntry,
	) (string, bool, error) {
		users := []string{}
		for _, e := range entries {
			users = append(users, e.Presence.UserId)
		}
		sort.Strings(users)
		key := strings.Join(users, ",")
		mu.Lock()
		hookAt[key] = time.Now()
		mu.Unlock()
		if key == "a1,a2" {
			// Stand-in for the runtime's allocation (container boot
			// and register, or an Edgegap deploy and READY poll).
			time.Sleep(hold)
		}
		return "", false, nil
	}

	add := func(uid, mode string) {
		sid, _ := uuid.NewV4()
		if _, _, err := mm.Add(context.Background(), []*MatchmakerPresence{{
			UserId: uid, SessionId: sid.String(), Username: uid,
			Node: "n", SessionID: sid,
		}}, sid.String(), "", "+properties.mode:"+mode, 2, 2, 1,
			map[string]string{"mode": mode}, map[string]float64{}); err != nil {
			t.Fatalf("add %s: %v", uid, err)
		}
	}
	waitFor := func(what string, cond func() bool, limit time.Duration) {
		deadline := time.Now().Add(limit)
		for time.Now().Before(deadline) {
			mu.Lock()
			ok := cond()
			mu.Unlock()
			if ok {
				return
			}
			time.Sleep(20 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for %s", what)
	}

	add("a1", "x")
	add("a2", "x")
	waitFor("first hook", func() bool { _, ok := hookAt["a1,a2"]; return ok }, 10*time.Second)
	// The second pair queues while the first hook (allocation) runs.
	time.Sleep(200 * time.Millisecond)
	add("b1", "y")
	add("b2", "y")
	queued := time.Now()
	waitFor("second envelope", func() bool { _, ok := envAt["b1"]; return ok }, hold+15*time.Second)
	waitFor("first envelope", func() bool { _, ok := envAt["a1"]; return ok }, 5*time.Second)

	mu.Lock()
	defer mu.Unlock()
	return hookAt["a1,a2"].Sub(start), queued.Sub(start),
		hookAt["b1,b2"].Sub(start), envAt["a1"].Sub(start), envAt["b1"].Sub(start)
}

func TestH37v2SlowHookStallsOtherMatches(t *testing.T) {
	for _, hold := range []time.Duration{0, 6 * time.Second} {
		fh, sq, sh, fe, se := h37v2Run(t, hold)
		r := func(d time.Duration) time.Duration { return d.Round(10 * time.Millisecond) }
		t.Logf("hold=%s: first hook +%s; second pair queued +%s;"+
			" second hook +%s; first pair envelope +%s;"+
			" second pair envelope +%s; second pair waited %s after queueing",
			hold, r(fh), r(sq), r(sh), r(fe), r(se), r(sh-sq))
		if hold > 0 && sh < fh+hold {
			t.Fatalf("second set matched while the first hook ran")
		}
	}
	t.Logf("PROBE: with interval_sec=1, an unrelated pair queued during a" +
		" slow hook is matched only after that hook returns")
}
