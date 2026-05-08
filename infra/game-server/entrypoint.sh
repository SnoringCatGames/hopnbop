#!/bin/bash
# Game-server entrypoint for Edgegap deployments. Registers the
# server with Nakama (so the platform knows how to route matched
# players here), then exec's the Godot Linux server. Godot binds
# 4433/UDP for ENet game data and 4434/TCP for WebRTC signaling
# (via SIGNALING_PORT env from the runtime hook); the
# signaling-proxy on the platform host fronts wss:// and bridges
# plain ws:// in to that port. No nginx, no per-container TLS.
#
# Edgegap injects deployment context as env vars (Arbitrium):
#   ARBITRIUM_PUBLIC_IP                Server's public IPv4
#   ARBITRIUM_PORT_GAME_EXTERNAL       Host UDP port mapped to
#                                      the "game" declared port
#   ARBITRIUM_PORT_SIGNALING_EXTERNAL  Host TCP port mapped to
#                                      the "signaling" declared
#                                      port
#   ARBITRIUM_REQUEST_ID               Edgegap deployment ID
#
# Variable names use the declared port NAME (game / signaling).
#
# Required from the runtime config:
#   NAKAMA_URL       Public Nakama URL.
#   NAKAMA_HTTP_KEY  Server-to-server key for unauthenticated
#                    RPCs (register_server, match_end).
set -euo pipefail

NAKAMA_URL="${NAKAMA_URL:-https://nakama.snoringcat.games}"
REQUEST_ID="${ARBITRIUM_REQUEST_ID:-}"
PUBLIC_IP="${ARBITRIUM_PUBLIC_IP:-}"
PORT="${ARBITRIUM_PORT_GAME_EXTERNAL:-4433}"

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

exec /game/hopnbop_server.x86_64 \
	--headless \
	-- --server
