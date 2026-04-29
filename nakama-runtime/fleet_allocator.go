package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

// edgegapClient wraps the Edgegap REST API.
type edgegapClient struct {
	token string
	http  *http.Client
}

func (c *edgegapClient) httpClient() *http.Client {
	if c.http == nil {
		c.http = &http.Client{Timeout: 30 * time.Second}
	}
	return c.http
}

type edgegapDeployRequest struct {
	AppName     string             `json:"app_name"`
	VersionName string             `json:"version_name"`
	IPList      []string           `json:"ip_list,omitempty"`
	EnvVars     []edgegapEnvKV     `json:"env_vars,omitempty"`
	IsPublicApp bool               `json:"is_public_app,omitempty"`
	Geographies []string           `json:"geographies,omitempty"`
	Filters     []map[string]any   `json:"filters,omitempty"`
}

type edgegapEnvKV struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

type edgegapDeployResponse struct {
	RequestID string `json:"request_id"`
	Message   string `json:"message"`
	// More fields depending on Edgegap API version.
}

type edgegapStatusResponse struct {
	RequestID     string                 `json:"request_id"`
	CurrentStatus string                 `json:"current_status"`
	PublicIP      string                 `json:"public_ip"`
	Ports         map[string]edgegapPort `json:"ports"`
	Fqdn          string                 `json:"fqdn"`
}

type edgegapPort struct {
	External int    `json:"external"`
	Internal int    `json:"internal"`
	Protocol string `json:"protocol"`
}

func (c *edgegapClient) Deploy(ctx context.Context, req edgegapDeployRequest) (*edgegapDeployResponse, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, "POST",
		"https://api.edgegap.com/v1/deploy", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "token "+c.token)

	resp, err := c.httpClient().Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("edgegap deploy failed (%d): %s", resp.StatusCode, string(respBody))
	}
	out := &edgegapDeployResponse{}
	if err := json.Unmarshal(respBody, out); err != nil {
		return nil, fmt.Errorf("decode deploy response: %w (body=%s)", err, string(respBody))
	}
	return out, nil
}

func (c *edgegapClient) Status(ctx context.Context, requestID string) (*edgegapStatusResponse, error) {
	url := fmt.Sprintf("https://api.edgegap.com/v1/status/%s", requestID)
	httpReq, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "token "+c.token)

	resp, err := c.httpClient().Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("edgegap status failed (%d): %s", resp.StatusCode, string(respBody))
	}
	out := &edgegapStatusResponse{}
	if err := json.Unmarshal(respBody, out); err != nil {
		return nil, fmt.Errorf("decode status response: %w (body=%s)", err, string(respBody))
	}
	return out, nil
}

// fleetAllocator hooks into MatchmakerMatched to spin up an Edgegap
// deployment for the matched players.
type fleetAllocator struct {
	edgegap    *edgegapClient
	appName    string
	appVersion string
}

// OnMatchmakerMatched is the Nakama matchmaker hook. Returning a
// non-empty match_id starts a multiplayer match. We use a custom
// flow: we don't return a Nakama match ID; instead we allocate an
// Edgegap deployment, then push a notification with connection
// info to the matched players.
func (a *fleetAllocator) OnMatchmakerMatched(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	entries []runtime.MatchmakerEntry,
) (string, error) {
	if len(entries) == 0 {
		return "", nil
	}
	logger.Info("matchmaker matched %d players, allocating Edgegap deployment", len(entries))

	// Collect player IPs (used by Edgegap for region selection).
	ipList := make([]string, 0, len(entries))
	playerIDs := make([]string, 0, len(entries))
	for _, e := range entries {
		props := e.GetProperties()
		if v, ok := props["client_ip"].(string); ok && v != "" {
			ipList = append(ipList, v)
		}
		playerIDs = append(playerIDs, e.GetPresence().GetUserId())
	}

	deploy, err := a.edgegap.Deploy(ctx, edgegapDeployRequest{
		AppName:     a.appName,
		VersionName: a.appVersion,
		IPList:      ipList,
	})
	if err != nil {
		logger.Error("edgegap deploy: %v", err)
		return "", err
	}
	logger.Info("edgegap request_id=%s, polling for ready", deploy.RequestID)

	// Poll for READY.
	pollCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	var status *edgegapStatusResponse
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		s, err := a.edgegap.Status(pollCtx, deploy.RequestID)
		if err != nil {
			logger.Warn("edgegap status check: %v", err)
		} else if s.CurrentStatus == "Status.READY" || s.CurrentStatus == "Ready" {
			status = s
			break
		}
		time.Sleep(2 * time.Second)
	}
	if status == nil {
		return "", fmt.Errorf("edgegap deployment %s did not become ready in 90s", deploy.RequestID)
	}

	// Notify each matched player with connection info.
	connInfo := map[string]any{
		"server_ip":   status.PublicIP,
		"server_fqdn": status.Fqdn,
		"ports":       status.Ports,
		"request_id":  status.RequestID,
	}
	connInfoJSON, _ := json.Marshal(connInfo)
	subject := "match_ready"
	for _, pid := range playerIDs {
		if err := nk.NotificationSend(ctx, pid, subject, map[string]any{
			"connection": string(connInfoJSON),
		}, 100, "", true); err != nil {
			logger.Warn("notify %s: %v", pid, err)
		}
	}

	// Return empty match ID — the actual realtime match runs on
	// the Edgegap-allocated game server, not inside Nakama.
	return "", nil
}
