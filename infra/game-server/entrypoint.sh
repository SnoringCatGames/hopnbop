#!/bin/bash
# Game-server entrypoint for Edgegap deployments. Registers the
# server with Nakama (so the platform knows how to route matched
# players here), boots an nginx TLS-termination layer for WebRTC
# signaling (when cert env vars are set), then exec's the Godot
# Linux server.
#
# Edgegap injects deployment context as env vars:
#   ARBITRARIUM_PUBLIC_IP                  Server's public IPv4
#   ARBITRARIUM_PORT_4433_UDP_EXTERNAL     External UDP port (game)
#   ARBITRARIUM_DEPLOY_REQUEST_ID          Edgegap deployment ID
#
# Required from the runtime config:
#   NAKAMA_URL       Public Nakama URL (https://nakama.snoringcat.games).
#   NAKAMA_HTTP_KEY  Server-to-server key for unauthenticated RPCs.
#
# Optional (set on the Edgegap app version, is_hidden=true):
#   TLS_FULLCHAIN    PEM-encoded fullchain for *.game.hopnbop.net.
#   TLS_PRIVKEY      PEM-encoded private key for the cert above.
#   When both are present, nginx is started for wss://
#   termination on 4434/TCP. When absent (e.g. ENet-only test
#   builds), nginx is skipped and the server runs without TLS
#   termination — clients in WebRTC mode would fail to connect,
#   but ENet-only matches still work.
#
# Note: per-deploy DNS pre-warming (`s-<ip>.game.hopnbop.net`)
# happens inside Nakama's matchmaker_matched hook, NOT here.
# We tried it from the container first; turns out Edgegap
# doesn't reliably inject CF creds at deploy time, and there
# is no clean way to view container stdout for diagnosis. The
# runtime has the same data (PublicIP from Edgegap status) and
# easier-to-read logs, so it owns the DNS lifecycle.
set -euo pipefail

NAKAMA_URL="${NAKAMA_URL:-https://nakama.snoringcat.games}"
REQUEST_ID="${ARBITRARIUM_DEPLOY_REQUEST_ID:-}"
PUBLIC_IP="${ARBITRARIUM_PUBLIC_IP:-}"
PORT="${ARBITRARIUM_PORT_4433_UDP_EXTERNAL:-4433}"

# --------------------------------------------------------------
# Register this allocation with the Nakama runtime so its
# matchmaker hook knows the server is live (for the
# version_check / register_server flow).
# --------------------------------------------------------------
if [[ -n "$REQUEST_ID" && -n "$PUBLIC_IP" && -n "${NAKAMA_HTTP_KEY:-}" ]]; then
	body=$(cat <<EOF
{"request_id":"$REQUEST_ID","server_ip":"$PUBLIC_IP","server_port":$PORT}
EOF
)
	# Nakama RPCs accept a quoted JSON string in the body when
	# called via HTTP gateway with http_key. The runtime module
	# unmarshals it.
	curl -fsS --max-time 10 -X POST \
		"${NAKAMA_URL}/v2/rpc/register_server?http_key=${NAKAMA_HTTP_KEY}" \
		-H "Content-Type: application/json" \
		-d "$(printf '%s' "$body" | jq -Rs .)" \
		|| echo "WARN: register_server RPC failed; continuing"
else
	echo "WARN: Edgegap or Nakama env vars missing; skipping register_server."
fi

# WebRTC signaling TLS termination via nginx. Only runs when
# both cert env vars are populated (they live on the Edgegap
# app version as is_hidden=true secrets, written there by the
# cert-rotate workflow).
if [[ -n "${TLS_FULLCHAIN:-}" && -n "${TLS_PRIVKEY:-}" ]]; then
	mkdir -p /game/tls /game/logs
	# Use printf to preserve newlines verbatim. echo -e mangles
	# multi-line PEM on some shells.
	printf '%s' "$TLS_FULLCHAIN" > /game/tls/fullchain.pem
	printf '%s' "$TLS_PRIVKEY"   > /game/tls/privkey.pem
	chmod 600 /game/tls/privkey.pem

	# Validate the cert+key match before starting nginx — a
	# mismatch here is a config error that nginx would
	# otherwise mask as a runtime failure mid-match.
	if ! openssl x509 -in /game/tls/fullchain.pem -noout >/dev/null 2>&1; then
		echo "ERROR: TLS_FULLCHAIN doesn't parse as a cert; nginx skipped"
	elif ! openssl pkey -in /game/tls/privkey.pem -noout >/dev/null 2>&1; then
		echo "ERROR: TLS_PRIVKEY doesn't parse as a private key; nginx skipped"
	else
		nginx -c /etc/nginx/nginx.conf -g 'daemon off;' &
		nginx_pid=$!
		echo "Started nginx (PID=$nginx_pid) for TLS termination on 4434/TCP"
	fi
else
	echo "TLS_FULLCHAIN / TLS_PRIVKEY not set; nginx skipped (web cross-play unavailable)."
fi

exec /game/hopnbop_server.x86_64 \
	--headless \
	-- --server
