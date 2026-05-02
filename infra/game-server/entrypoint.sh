#!/bin/bash
# Game-server entrypoint for Edgegap deployments. Registers the
# server with Nakama (so the platform knows how to route matched
# players here), then exec's the Godot Linux server.
#
# Replaces the GameLift-era entrypoint, which fetched a TLS cert
# from Secrets Manager, started nginx for WSS termination, and
# created a Route 53 A record per server. Edgegap port-forwards
# declared container ports directly, so none of that is needed.
#
# Edgegap injects deployment context as env vars:
#   ARBITRARIUM_PUBLIC_IP                  Server's public IPv4
#   ARBITRARIUM_PORT_4433_UDP_EXTERNAL     External UDP port (game)
#   ARBITRARIUM_DEPLOY_REQUEST_ID          Edgegap deployment ID
#
# Required from the runtime config:
#   NAKAMA_URL       Public Nakama URL (https://nakama.snoringcat.games).
#   NAKAMA_HTTP_KEY  Server-to-server key for unauthenticated RPCs.
set -euo pipefail

NAKAMA_URL="${NAKAMA_URL:-https://nakama.snoringcat.games}"
REQUEST_ID="${ARBITRARIUM_DEPLOY_REQUEST_ID:-}"
PUBLIC_IP="${ARBITRARIUM_PUBLIC_IP:-}"
PORT="${ARBITRARIUM_PORT_4433_UDP_EXTERNAL:-4433}"

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

exec /game/hopnbop_server.x86_64 \
	--headless \
	-- --server
