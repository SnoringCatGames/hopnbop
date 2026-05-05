#!/bin/bash
# Game-server entrypoint for Edgegap deployments. Registers the
# server with Nakama (so the platform knows how to route matched
# players here), pre-warms the deploy's public DNS A record on
# Cloudflare, boots an nginx TLS-termination layer for WebRTC
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
# Optional (set on the Edgegap app version, is_secret=true):
#   CLOUDFLARE_DNS_TOKEN     CF API token, scoped Zone:DNS:Edit on
#                            the SERVER_DNS_BASE zone.
#   CLOUDFLARE_DNS_ZONE_ID   CF zone ID for SERVER_DNS_BASE
#                            (e.g. snoringcat.games / hopnbop.net).
#   SERVER_DNS_BASE          Apex used for the per-deploy hostname,
#                            e.g. "game.hopnbop.net". Defaults to
#                            game.hopnbop.net when unset.
#   When all three are present, the entrypoint registers
#   `s-<ip-with-dashes>.<SERVER_DNS_BASE>` -> $PUBLIC_IP as a
#   short-TTL A record at startup, and deletes it on EXIT/SIGTERM.
#   The runtime hook computes the same name from PublicIP and
#   sends it to clients in match_ready, so the wildcard cert at
#   *.<SERVER_DNS_BASE> matches the client's WSS handshake.
set -euo pipefail

NAKAMA_URL="${NAKAMA_URL:-https://nakama.snoringcat.games}"
REQUEST_ID="${ARBITRARIUM_DEPLOY_REQUEST_ID:-}"
PUBLIC_IP="${ARBITRARIUM_PUBLIC_IP:-}"
PORT="${ARBITRARIUM_PORT_4433_UDP_EXTERNAL:-4433}"
SERVER_DNS_BASE="${SERVER_DNS_BASE:-game.hopnbop.net}"

# --------------------------------------------------------------
# Cloudflare DNS pre-warming. Skipped if any required env var
# is missing — the server still boots, but web clients won't be
# able to complete WSS handshakes (cert mismatch on the
# Edgegap-provided FQDN).
# --------------------------------------------------------------
DNS_RECORD_ID=""
HOSTNAME=""
echo "DNS pre-warm: token_set=$([[ -n "${CLOUDFLARE_DNS_TOKEN:-}" ]] && echo yes || echo no)" \
	"zone_set=$([[ -n "${CLOUDFLARE_DNS_ZONE_ID:-}" ]] && echo yes || echo no)" \
	"public_ip=${PUBLIC_IP:-(unset)} base=${SERVER_DNS_BASE}"
if [[ -n "${CLOUDFLARE_DNS_TOKEN:-}" \
		&& -n "${CLOUDFLARE_DNS_ZONE_ID:-}" \
		&& -n "$PUBLIC_IP" ]]; then
	HOSTNAME="s-${PUBLIC_IP//./-}.${SERVER_DNS_BASE}"
	# 60s TTL: long enough that browser DNS caching helps
	# during a session, short enough that stale records
	# (after a SIGKILL exit, say) clear quickly.
	create_body=$(jq -nc \
		--arg name    "$HOSTNAME" \
		--arg ip      "$PUBLIC_IP" \
		--arg comment "edgegap deploy=${REQUEST_ID:-unknown} created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		'{type:"A",name:$name,content:$ip,ttl:60,proxied:false,comment:$comment}')
	# Capture stderr too — when --fsS hides the body on non-2xx,
	# we still want stderr in the log for diagnosis.
	create_response=$(curl -sS --max-time 10 -X POST \
		"https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_DNS_ZONE_ID}/dns_records" \
		-H "Authorization: Bearer ${CLOUDFLARE_DNS_TOKEN}" \
		-H "Content-Type: application/json" \
		-d "$create_body" 2>&1) || true
	echo "DNS pre-warm: CF API response: $create_response"
	DNS_RECORD_ID=$(printf '%s' "$create_response" | jq -r '.result.id // empty' 2>/dev/null || true)
	if [[ -n "$DNS_RECORD_ID" ]]; then
		echo "DNS A record created: $HOSTNAME -> $PUBLIC_IP (id=$DNS_RECORD_ID)"
		# Delete on graceful exit. Edgegap may still SIGKILL
		# the container, in which case the daily watchdog
		# (infra/remote/dns-watchdog/) cleans up. Best-effort
		# either way — a stale record points at a dead IP for
		# at most one TTL until the watchdog or a re-deploy
		# replaces it.
		cleanup_dns() {
			curl -fsS --max-time 10 -X DELETE \
				"https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_DNS_ZONE_ID}/dns_records/${DNS_RECORD_ID}" \
				-H "Authorization: Bearer ${CLOUDFLARE_DNS_TOKEN}" \
				>/dev/null 2>&1 \
				&& echo "DNS A record deleted: $HOSTNAME (id=$DNS_RECORD_ID)" \
				|| echo "WARN: failed to delete DNS record $DNS_RECORD_ID"
		}
		trap cleanup_dns EXIT TERM INT
	else
		echo "WARN: DNS A record creation failed; web cross-play may not connect."
	fi
else
	echo "INFO: required env vars not all set; skipping DNS pre-warm."
fi

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
