package main

// H37 phase 2b probe (agent h37-verify2), not part of the platform repo.
// It lives only in a copy of the runtime package under
// hopnbop/.claude/probes/H37/h37-verify2/runtime-copy/. It drives the
// real OnMatchmakerMatched hook in local allocator mode. Docker is an
// in-memory RoundTripper and Nakama a fake NakamaModule, so nothing
// binds a port, touches Docker or reaches a backend.

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

// --- Fakes ---

type h37v2Presence struct{ uid string }

func (p h37v2Presence) GetHidden() bool                 { return false }
func (p h37v2Presence) GetPersistence() bool            { return false }
func (p h37v2Presence) GetUsername() string             { return "u-" + p.uid[:4] }
func (p h37v2Presence) GetStatus() string               { return "" }
func (p h37v2Presence) GetReason() runtime.PresenceReason { return runtime.PresenceReasonUnknown }
func (p h37v2Presence) GetUserId() string               { return p.uid }
func (p h37v2Presence) GetSessionId() string            { return "sess-" + p.uid[:4] }
func (p h37v2Presence) GetNodeId() string               { return "node" }

type h37v2Entry struct {
	uid   string
	props map[string]interface{}
}

func (e h37v2Entry) GetPresence() runtime.Presence         { return h37v2Presence{uid: e.uid} }
func (e h37v2Entry) GetTicket() string                     { return "ticket-" + e.uid[:4] }
func (e h37v2Entry) GetProperties() map[string]interface{} { return e.props }
func (e h37v2Entry) GetPartyId() string                    { return "" }

type h37v2Note struct {
	userID  string
	subject string
	content map[string]interface{}
	at      time.Time
}

// h37v2Nk answers the calls the hook makes. A server_registrations row
// exists only once `registeredAt` has passed, which models a container
// that takes that long to boot and call register_server.
type h37v2Nk struct {
	runtime.NakamaModule
	mu           sync.Mutex
	notes        []h37v2Note
	registeredAt time.Time
}

func (n *h37v2Nk) StorageRead(
	_ context.Context, reads []*runtime.StorageRead,
) ([]*api.StorageObject, error) {
	out := []*api.StorageObject{}
	for _, r := range reads {
		if r.Collection == "server_registrations" &&
			time.Now().After(n.registeredAt) {
			out = append(out, &api.StorageObject{
				Collection: r.Collection, Key: r.Key, Value: "{}",
			})
		}
	}
	return out, nil
}

func (n *h37v2Nk) StorageWrite(
	_ context.Context, writes []*runtime.StorageWrite,
) ([]*api.StorageObjectAck, error) {
	acks := []*api.StorageObjectAck{}
	for _, w := range writes {
		acks = append(acks, &api.StorageObjectAck{
			Collection: w.Collection, Key: w.Key,
		})
	}
	return acks, nil
}

func (n *h37v2Nk) FriendsList(
	_ context.Context, _ string, _ int, _ *int, _ string,
) ([]*api.Friend, string, error) {
	return nil, "", nil
}

func (n *h37v2Nk) NotificationSend(
	_ context.Context, userID, subject string,
	content map[string]interface{}, _ int, _ string, _ bool,
) error {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.notes = append(n.notes, h37v2Note{
		userID: userID, subject: subject, content: content,
		at: time.Now(),
	})
	return nil
}

func (n *h37v2Nk) MetricsTimerRecord(string, map[string]string, time.Duration) {}
func (n *h37v2Nk) MetricsCounterAdd(string, map[string]string, int64)          {}
func (n *h37v2Nk) MetricsGaugeSet(string, map[string]string, float64)          {}

func (n *h37v2Nk) snapshot() []h37v2Note {
	n.mu.Lock()
	defer n.mu.Unlock()
	return append([]h37v2Note(nil), n.notes...)
}

type h37v2Docker struct {
	mu        sync.Mutex
	createEnv []string
	calls     []string
}

func (f *h37v2Docker) RoundTrip(r *http.Request) (*http.Response, error) {
	f.mu.Lock()
	f.calls = append(f.calls, r.Method+" "+r.URL.Path)
	f.mu.Unlock()
	status := http.StatusNoContent
	body := ""
	switch {
	case strings.HasSuffix(r.URL.Path, "/containers/create"):
		raw, _ := io.ReadAll(r.Body)
		var req dockerCreateContainerRequest
		_ = json.Unmarshal(raw, &req)
		f.mu.Lock()
		f.createEnv = req.Env
		f.mu.Unlock()
		status = http.StatusCreated
		body = `{"Id":"c-` + r.URL.Query().Get("name") + `"}`
	case strings.HasSuffix(r.URL.Path, "/json"):
		status = http.StatusOK
		body = `{"NetworkSettings":{"Networks":{"probe-net":` +
			`{"IPAddress":"10.0.0.2"}}}}`
	}
	return &http.Response{
		StatusCode: status,
		Body:       io.NopCloser(strings.NewReader(body)),
		Header:     http.Header{},
		Request:    r,
	}, nil
}

func (f *h37v2Docker) env(key string) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, kv := range f.createEnv {
		if strings.HasPrefix(kv, key+"=") {
			return strings.TrimPrefix(kv, key+"=")
		}
	}
	return ""
}

const h37v2GameConfig = `{"game_id":"probe","allocator_mode":"local",` +
	`"local_image_ref":"probe:latest"}`

// Two UUID-shaped user ids, as Nakama mints them.
const (
	h37v2UserA = "3f2b9c1e-6a4d-4e8b-9d21-5c7a0e4f8b13"
	h37v2UserB = "8d61a0f4-2c3e-4b7a-a9f5-0e1d2c3b4a59"
)

func h37v2Setup(t *testing.T) (*fleetAllocator, *perGameConfig, *h37v2Docker) {
	t.Helper()
	games := newTestGames(t, map[string]string{"probe": h37v2GameConfig})
	fd := &h37v2Docker{}
	udpLo, udpHi, _ := parsePortRange("30000-30099")
	tcpLo, tcpHi, _ := parsePortRange("30100-30199")
	local := &LocalDockerAllocator{
		dockerSocket:  "/nonexistent.sock",
		publicIP:      "203.0.113.10",
		httpKey:       "probe",
		dockerNetwork: "probe-net",
		nakamaURL:     "http://nakama:7350",
		ports:         newLocalPortPool(udpLo, udpHi, tcpLo, tcpHi),
		http:          &http.Client{Transport: fd},
	}
	alloc := &fleetAllocator{
		local:               local,
		games:               games,
		appName:             "probe",
		appVersion:          "v1",
		signalingDomain:     "signaling.example.invalid",
		signalingHmacSecret: []byte("probe-secret"),
	}
	return alloc, games, fd
}

func h37v2Entries() []runtime.MatchmakerEntry {
	// A plays couch co-op with 2 local players, B alone. These are
	// the string properties the SDK puts on the ticket, which Nakama
	// copies into every recipient's MatchmakerMatched envelope.
	return []runtime.MatchmakerEntry{
		h37v2Entry{uid: h37v2UserA, props: map[string]interface{}{
			"player_count": "2", "game_id": "probe", "platform": "windows",
		}},
		h37v2Entry{uid: h37v2UserB, props: map[string]interface{}{
			"player_count": "1", "game_id": "probe", "platform": "windows",
		}},
	}
}

// --- G1.2: the allowlist is computable from the matchmaker envelope ---

// What every matched player receives from Nakama itself (3.25.0
// server/matchmaker.go: users[] carries each entry's Presence.UserId and
// StringProperties): enough to compute every session id the runtime
// mints, without the runtime's per-player match_ready payload.
func h37v2PredictFromEnvelope(entries []runtime.MatchmakerEntry) []string {
	out := []string{}
	for _, e := range entries {
		n := 1
		if raw, ok := e.GetProperties()["player_count"].(string); ok {
			if v, err := strconv.Atoi(raw); err == nil && v > 0 {
				n = v
			}
		}
		for i := 0; i < n; i++ {
			out = append(out, e.GetPresence().GetUserId()+"_"+strconv.Itoa(i))
		}
	}
	sort.Strings(out)
	return out
}

func TestH37v2SessionIDsDerivableFromEnvelope(t *testing.T) {
	alloc, _, fd := h37v2Setup(t)
	nk := &h37v2Nk{registeredAt: time.Now()}
	entries := h37v2Entries()

	if _, err := alloc.OnMatchmakerMatched(
		context.Background(), testLogger{}, nil, nk, entries,
	); err != nil {
		t.Fatalf("hook: %v", err)
	}

	allow := strings.Split(fd.env("EXPECTED_SESSION_IDS"), ",")
	sort.Strings(allow)
	predicted := h37v2PredictFromEnvelope(entries)
	t.Logf("EXPECTED_SESSION_IDS given to the server: %v", allow)
	t.Logf("computed from the envelope (user ids + player_count): %v",
		predicted)
	if strings.Join(allow, ",") != strings.Join(predicted, ",") {
		t.Fatalf("allowlist %v != predicted %v", allow, predicted)
	}

	// Each match_ready carries only the recipient's own ids, so the
	// runtime treats them as per-player secrets.
	for _, n := range nk.snapshot() {
		if n.subject != "match_ready" {
			continue
		}
		var conn map[string]interface{}
		_ = json.Unmarshal([]byte(n.content["connection"].(string)), &conn)
		t.Logf("match_ready to %s...: session_ids=%v server=%v",
			n.userID[:8], conn["session_ids"], conn["server_ip"])
		for _, sid := range conn["session_ids"].([]interface{}) {
			if !strings.HasPrefix(sid.(string), n.userID+"_") {
				t.Fatalf("sid %v is not <recipient uid>_<n>", sid)
			}
		}
	}
	t.Logf("PROBE: player A can compute B's session id %s_0 from the"+
		" envelope alone; it is on the server's allowlist", h37v2UserB)
}

// --- Finding 3, runtime half: the hook holds for the whole allocation ---

func TestH37v2HookBlocksForWholeAllocation(t *testing.T) {
	alloc, _, _ := h37v2Setup(t)
	const boot = 3 * time.Second
	start := time.Now()
	nk := &h37v2Nk{registeredAt: start.Add(boot)}

	if _, err := alloc.OnMatchmakerMatched(
		context.Background(), testLogger{}, nil, nk, h37v2Entries(),
	); err != nil {
		t.Fatalf("hook: %v", err)
	}
	returned := time.Since(start)
	t.Logf("hook returned after %s (container registers after %s)",
		returned.Round(time.Millisecond), boot)
	if returned < boot {
		t.Fatalf("hook returned before the server registered")
	}
	ready := 0
	for _, n := range nk.snapshot() {
		if n.subject == "match_ready" {
			ready++
			t.Logf("match_ready to %s... at +%s", n.userID[:8],
				n.at.Sub(start).Round(time.Millisecond))
		}
	}
	if ready != 2 {
		t.Fatalf("want 2 match_ready, got %d", ready)
	}
	t.Logf("PROBE: OnMatchmakerMatched is synchronous; it returns only" +
		" after the allocation (container boot + register) completes")
}

// --- Finding 4: one user's cancel aborts the whole matched set ---

func TestH37v2OneUserCancelAbortsMatchedSet(t *testing.T) {
	alloc, games, fd := h37v2Setup(t)
	start := time.Now()
	// The container is still booting for the whole test.
	nk := &h37v2Nk{registeredAt: start.Add(time.Hour)}

	done := make(chan time.Duration, 1)
	go func() {
		_, _ = alloc.OnMatchmakerMatched(
			context.Background(), testLogger{}, nil, nk, h37v2Entries())
		done <- time.Since(start)
	}()

	time.Sleep(700 * time.Millisecond)
	// What the SDK sends when user A's 120 s timer fires
	// (matchmaker_api_client.gd _on_elapsed_tick -> cancel_matchmaking
	// -> cancel_matchmaking_allocation).
	rpc := cancelAllocationRpcFactory(alloc, games)
	ctx := context.WithValue(context.Background(),
		runtime.RUNTIME_CTX_USER_ID, h37v2UserA)
	ctx = context.WithValue(ctx, runtime.RUNTIME_CTX_VARS,
		map[string]string{"game_id": "probe"})
	resp, err := rpc(ctx, testLogger{}, nil, nk, "{}")
	t.Logf("cancel_matchmaking_allocation as A -> %s err=%v", resp, err)

	select {
	case d := <-done:
		t.Logf("hook returned after %s", d.Round(time.Millisecond))
	case <-time.After(5 * time.Second):
		t.Fatalf("hook did not return after the cancel")
	}

	got := map[string]string{}
	for _, n := range nk.snapshot() {
		t.Logf("notify %s...: %s %v", n.userID[:8], n.subject, n.content)
		if n.subject == "match_ready" {
			t.Fatalf("match_ready sent despite the cancel")
		}
		if n.subject == "match_failed" {
			got[n.userID], _ = n.content["reason"].(string)
		}
	}
	if got[h37v2UserA] != "cancelled" || got[h37v2UserB] != "cancelled" {
		t.Fatalf("want both users match_failed/cancelled, got %v", got)
	}
	fd.mu.Lock()
	t.Logf("docker calls: %v", fd.calls)
	fd.mu.Unlock()
	t.Logf("PROBE: A's cancel aborted the shared allocation; B, who did" +
		" not cancel, got match_failed reason=cancelled")
}
