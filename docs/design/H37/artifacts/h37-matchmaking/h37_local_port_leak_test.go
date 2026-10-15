package main

// H37 probe, not part of the platform repo. It lives only in a copy of
// the runtime package under hopnbop/.claude/probes/H37/h37-matchmaking/.
// It shows that LocalDockerAllocator.Stop never returns a match's
// UDP/TCP port pair to the pool. Docker is an in-memory RoundTripper and
// Nakama a stub StorageRead, so nothing binds a port or touches Docker.

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

type h37FakeDocker struct{ calls []string }

func (f *h37FakeDocker) RoundTrip(r *http.Request) (*http.Response, error) {
	f.calls = append(f.calls, r.Method+" "+r.URL.Path)
	status := http.StatusNoContent
	body := ""
	switch {
	case strings.HasSuffix(r.URL.Path, "/containers/create"):
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

// h37RegisteredNk answers every storage read with a row, so
// waitForServerRegistered returns on its first poll.
type h37RegisteredNk struct{ runtime.NakamaModule }

func (h37RegisteredNk) StorageRead(
	_ context.Context, reads []*runtime.StorageRead,
) ([]*api.StorageObject, error) {
	out := []*api.StorageObject{}
	for _, r := range reads {
		out = append(out, &api.StorageObject{
			Collection: r.Collection, Key: r.Key, Value: "{}",
		})
	}
	return out, nil
}

func h37NewAllocator() (*LocalDockerAllocator, *h37FakeDocker) {
	fd := &h37FakeDocker{}
	// Production ranges: scripts/lib/nakama-env.ps1:89-90.
	udpLo, udpHi, _ := parsePortRange("30000-30099")
	tcpLo, tcpHi, _ := parsePortRange("30100-30199")
	return &LocalDockerAllocator{
		dockerSocket:  "/nonexistent.sock",
		publicIP:      "203.0.113.10",
		httpKey:       "probe",
		dockerNetwork: "probe-net",
		nakamaURL:     "http://nakama:7350",
		ports:         newLocalPortPool(udpLo, udpHi, tcpLo, tcpHi),
		http:          &http.Client{Transport: fd},
	}, fd
}

// Every match is allocated and then stopped (the match_end or
// match_cancel path), so at most one container exists at any time. A
// pool that released on Stop would never run dry.
func TestH37LocalStopLeaksPortPair(t *testing.T) {
	l, fd := h37NewAllocator()
	gc := &GameConfig{GameID: "probe", LocalImageRef: "probe:latest"}
	ctx := context.Background()
	completed := 0
	var lastErr error
	for i := 0; i < 150; i++ {
		deploy, _, err := l.Allocate(
			ctx, testLogger{}, h37RegisteredNk{}, gc,
			edgegapDeployRequest{})
		if err != nil {
			lastErr = err
			break
		}
		if err := l.Stop(ctx, deploy.RequestID); err != nil {
			t.Fatalf("stop %d: %v", i, err)
		}
		completed++
	}
	t.Logf("sequential allocate+Stop cycles that succeeded: %d", completed)
	t.Logf("pool in use after every Stop: udp=%d tcp=%d",
		len(l.ports.udpInUse), len(l.ports.tcpInUse))
	t.Logf("docker calls made: %d", len(fd.calls))
	if lastErr == nil {
		t.Fatalf("no exhaustion after 150 cycles: Stop releases ports")
	}
	t.Logf("allocation %d failed: %v", completed+1, lastErr)
}
