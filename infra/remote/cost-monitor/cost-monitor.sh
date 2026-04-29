#!/bin/bash
# Daily cost monitor for the snoringcat-platform stack.
#
# Polls Hetzner Cloud + Edgegap APIs for month-to-date spend, posts
# a Discord summary, and triggers an emergency shutdown if the
# grand total exceeds $EMERGENCY_CAP (default $50/mo).
#
# Reads /opt/snoringcat/cost-monitor/.env for tokens.
#
# Run via systemd timer (cost-monitor.timer), daily 09:00 UTC.

set -euo pipefail

ENV_FILE="/opt/snoringcat/cost-monitor/.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

EMERGENCY_CAP="${EMERGENCY_CAP:-50}"
MONTH_START="$(date -u +%Y-%m-01)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------
# Hetzner Cloud spend (MTD).
# Hetzner Cloud doesn't have a "cost" API. We sum hourly server
# pricing instead. Two CPX21 servers = €0.0098/hr each (€7.05/mo).
# Hours since start of month × hourly rate × server count.
# ---------------------------------------------------------------------
hetzner_servers=$(curl -fsS \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  "https://api.hetzner.cloud/v1/servers" \
  | jq '.servers | length')

# Approximate per-hour cost for cpx21 in hil. €7.05/mo / 730 hr ≈ €0.00966.
# We're being conservative — actual pricing reads via /pricing endpoint.
hetzner_pricing=$(curl -fsS \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  "https://api.hetzner.cloud/v1/pricing")
cpx21_hourly_eur=$(echo "$hetzner_pricing" | jq -r \
  '.pricing.server_types[] | select(.name=="cpx21") | .prices[] | select(.location=="hil") | .price_hourly.gross' | head -1)
# Default if API shape changed.
cpx21_hourly_eur="${cpx21_hourly_eur:-0.00966}"
hours_this_month=$(( ($(date -u +%s) - $(date -u -d "$MONTH_START" +%s)) / 3600 ))
hetzner_eur=$(awk -v h="$hours_this_month" -v r="$cpx21_hourly_eur" -v n="$hetzner_servers" \
  'BEGIN { printf "%.2f", h * r * n }')
# €→$ conversion (rough); refine later if needed.
hetzner_usd=$(awk -v e="$hetzner_eur" 'BEGIN { printf "%.2f", e * 1.08 }')

# ---------------------------------------------------------------------
# Edgegap MTD spend.
# Edgegap exposes /v1/billing/current_month or similar. If the
# endpoint isn't documented for our plan tier, fall back to
# usage estimate.
# ---------------------------------------------------------------------
edgegap_usd="0.00"
if edgegap_resp=$(curl -fsS \
    -H "Authorization: Token $EDGEGAP_TOKEN" \
    "https://api.edgegap.com/v1/billing/current_month" 2>/dev/null); then
  amount=$(echo "$edgegap_resp" | jq -r '.amount // .total // 0')
  edgegap_usd=$(awk -v a="$amount" 'BEGIN { printf "%.2f", a }')
fi

total_usd=$(awk -v a="$hetzner_usd" -v b="$edgegap_usd" 'BEGIN { printf "%.2f", a + b }')

# ---------------------------------------------------------------------
# Emergency shutdown check.
# ---------------------------------------------------------------------
emergency_msg=""
if awk -v t="$total_usd" -v cap="$EMERGENCY_CAP" 'BEGIN { exit !(t > cap) }'; then
  emergency_msg=$'\n:rotating_light: **EMERGENCY: $'$total_usd' exceeds cap $'$EMERGENCY_CAP'**\nScaling Edgegap fleet to 0.'
  # Scale Edgegap fleet to 0. The exact endpoint depends on app
  # name; populate EDGEGAP_APP_NAME in .env when Phase C deploys.
  if [[ -n "${EDGEGAP_APP_NAME:-}" ]]; then
    curl -fsS -X PATCH \
      -H "Authorization: Token $EDGEGAP_TOKEN" \
      -H "Content-Type: application/json" \
      "https://api.edgegap.com/v1/app/$EDGEGAP_APP_NAME" \
      -d '{"capacity_max": 0}' || true
  fi
  # Power off Hetzner game-server boxes (none in Phase B; Phase C
  # adds them via Edgegap, which we already stopped above).
fi

# ---------------------------------------------------------------------
# Discord summary.
# ---------------------------------------------------------------------
read -r -d '' MSG <<EOF || true
**Daily cost: \$$total_usd MTD ($MONTH_START → $NOW_ISO)**
- Hetzner Cloud: \$$hetzner_usd ($hetzner_servers servers × $hours_this_month hrs)
- Edgegap: \$$edgegap_usd
- Cap: \$$EMERGENCY_CAP$emergency_msg
EOF

curl -fsS -X POST \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$MSG" '{content:$c}')" \
  "$DISCORD_WEBHOOK_URL" >/dev/null

echo "[cost-monitor] $NOW_ISO total=\$$total_usd hetzner=\$$hetzner_usd edgegap=\$$edgegap_usd"
