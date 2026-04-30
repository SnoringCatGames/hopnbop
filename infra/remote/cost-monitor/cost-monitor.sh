#!/bin/bash
# Hourly cost monitor for the snoringcat-platform stack.
#
# Each run: compute MTD spend, decide whether to alert.
# - Threshold crossings (LOW / MID / HIGH / EMERGENCY) fire a
#   Discord ping immediately, gated by a state file so we don't
#   re-alert every hour for the same threshold.
# - One routine "Daily cost" summary per day, posted at
#   $DAILY_SUMMARY_HOUR_UTC (default 09:00).
# - Other runs are silent.
#
# The EMERGENCY threshold also scales the Edgegap fleet to 0
# (capacity_max=0 via PATCH), halting new allocations.
#
# Reads /opt/snoringcat/cost-monitor/.env for tokens + thresholds.

set -euo pipefail

ENV_FILE="/opt/snoringcat/cost-monitor/.env"
STATE_FILE_DEFAULT="/var/lib/snoringcat/cost-monitor-state.json"

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

EMERGENCY_CAP="${EMERGENCY_CAP:-50}"
BUDGET_WARN_LOW="${BUDGET_WARN_LOW:-20}"
BUDGET_WARN_MID="${BUDGET_WARN_MID:-40}"
BUDGET_WARN_HIGH="${BUDGET_WARN_HIGH:-80}"
DAILY_SUMMARY_HOUR_UTC="${DAILY_SUMMARY_HOUR_UTC:-9}"
DISCORD_USER_ID="${DISCORD_USER_ID:-}"
STATE_FILE="${STATE_FILE:-$STATE_FILE_DEFAULT}"

CURRENT_MONTH="$(date -u +%Y-%m)"
CURRENT_DAY="$(date -u +%Y-%m-%d)"
CURRENT_HOUR_UTC="$(date -u +%-H)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"
MONTH_START_EPOCH="$(date -u -d "${CURRENT_MONTH}-01" +%s)"

mkdir -p "$(dirname "$STATE_FILE")"

# ---------------------------------------------------------------------
# State
# ---------------------------------------------------------------------
state="{}"
if [[ -f "$STATE_FILE" ]]; then
	state=$(cat "$STATE_FILE")
fi
state_month=$(echo "$state" | jq -r '.month // ""')
if [[ "$state_month" != "$CURRENT_MONTH" ]]; then
	state=$(jq -n --arg m "$CURRENT_MONTH" \
		'{month:$m, thresholds_crossed:[], last_summary_day:""}')
fi

# ---------------------------------------------------------------------
# Hetzner spend (MTD).
# Real model: Hetzner caps at the monthly rate. Pro-rata up to the
# cap, per server, since the later of (server creation, start of
# month). Use net price (no VAT for US accounts).
# ---------------------------------------------------------------------
hetzner_eur="0.00"
servers_json=$(curl -fsS \
	-H "Authorization: Bearer $HCLOUD_TOKEN" \
	"https://api.hetzner.cloud/v1/servers")
pricing_json=$(curl -fsS \
	-H "Authorization: Bearer $HCLOUD_TOKEN" \
	"https://api.hetzner.cloud/v1/pricing")

hetzner_eur=$(echo "$servers_json" | jq -r --arg now "$NOW_EPOCH" \
	--arg month_start "$MONTH_START_EPOCH" \
	--argjson pricing "$pricing_json" '
	def hourly_net($srv_type; $loc):
		($pricing.pricing.server_types[]
			| select(.name == $srv_type) | .prices[]
			| select(.location == $loc) | .price_hourly.net | tonumber);
	def monthly_net($srv_type; $loc):
		($pricing.pricing.server_types[]
			| select(.name == $srv_type) | .prices[]
			| select(.location == $loc) | .price_monthly.net | tonumber);
	[.servers[] | {
		name: .name,
		type: .server_type.name,
		loc: .datacenter.location.name,
		created_epoch: (.created | sub("\\.[0-9]+\\+"; "+") | fromdate),
	} | . + {
		hours_this_month: (
			((($now | tonumber)
				- ([.created_epoch, ($month_start | tonumber)] | max))
				/ 3600) | floor
		),
		hourly: hourly_net(.type; .loc),
		monthly_cap: monthly_net(.type; .loc),
	} | . + {
		eur: ([.hours_this_month * .hourly, .monthly_cap] | min)
	}] | map(.eur) | add // 0' 2>/dev/null || echo "0")
hetzner_usd=$(awk -v e="$hetzner_eur" 'BEGIN { printf "%.2f", e * 1.08 }')

# ---------------------------------------------------------------------
# Edgegap MTD spend.
# ---------------------------------------------------------------------
edgegap_usd="0.00"
if edgegap_resp=$(curl -fsS \
		-H "Authorization: Token $EDGEGAP_TOKEN" \
		"https://api.edgegap.com/v1/billing/current_month" 2>/dev/null); then
	amount=$(echo "$edgegap_resp" | jq -r '.amount // .total // 0' 2>/dev/null || echo 0)
	edgegap_usd=$(awk -v a="$amount" 'BEGIN { printf "%.2f", a }')
fi

total_usd=$(awk -v a="$hetzner_usd" -v b="$edgegap_usd" \
	'BEGIN { printf "%.2f", a + b }')

# ---------------------------------------------------------------------
# Cloudflare R2 storage usage.
# Free tier: 10 GB storage / 1M class-A ops / 10M class-B / mo.
# Egress is free. Storage is the only realistic overage risk for
# this project. Class-A/B requests would need millions/day to
# matter — not modeled here.
#
# We use list-objects + sum because the /usage endpoint
# aggregates with hourly+ lag and reports 0 for bucket changes
# that happened in the last hour. List-objects is real-time.
# Pagination caps at 1000 per call; for our 4-file bucket we
# fit in one page comfortably.
# ---------------------------------------------------------------------
r2_bytes="0"
r2_gb="0.00"
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" \
		&& -n "${CLOUDFLARE_ACCOUNT_ID:-}" \
		&& -n "${R2_BUCKET:-}" ]]; then
	cursor=""
	r2_bytes=0
	while :; do
		url="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$R2_BUCKET/objects?per_page=1000"
		[[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
		if ! resp=$(curl -fsS \
				-H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
				"$url" 2>/dev/null); then
			break
		fi
		page_sum=$(echo "$resp" | jq '[.result[].size] | add // 0' 2>/dev/null || echo 0)
		r2_bytes=$((r2_bytes + page_sum))
		cursor=$(echo "$resp" | jq -r '.result_info.cursor // ""' 2>/dev/null)
		[[ -z "$cursor" || "$cursor" == "null" ]] && break
	done
	r2_gb=$(awk -v b="$r2_bytes" 'BEGIN { printf "%.2f", b / (1024*1024*1024) }')
fi

# ---------------------------------------------------------------------
# Threshold crossings.
# ---------------------------------------------------------------------
already_crossed=$(echo "$state" | jq -r '.thresholds_crossed[]' 2>/dev/null \
	| sort -u)
declare -a new_crossings=()
for entry in "low:$BUDGET_WARN_LOW" "mid:$BUDGET_WARN_MID" \
		"high:$BUDGET_WARN_HIGH" "emergency:$EMERGENCY_CAP"; do
	name="${entry%:*}"
	value="${entry#*:}"
	if awk -v t="$total_usd" -v v="$value" 'BEGIN { exit !(t >= v) }'; then
		if ! echo "$already_crossed" | grep -qx "$name"; then
			new_crossings+=("$name:$value")
			state=$(echo "$state" | jq --arg n "$name" \
				'.thresholds_crossed += [$n]')
		fi
	fi
done

# R2 size thresholds. Use the same crossings array so a single
# Discord message covers everything.
for entry in "r2_warn:${R2_WARN_GB:-8}" "r2_hard:${R2_HARD_GB:-9.5}"; do
	name="${entry%:*}"
	value="${entry#*:}"
	if awk -v t="$r2_gb" -v v="$value" 'BEGIN { exit !(t >= v) }'; then
		if ! echo "$already_crossed" | grep -qx "$name"; then
			new_crossings+=("$name:${value}GB")
			state=$(echo "$state" | jq --arg n "$name" \
				'.thresholds_crossed += [$n]')
		fi
	fi
done

# ---------------------------------------------------------------------
# Emergency action.
# ---------------------------------------------------------------------
emergency_msg=""
if (( ${#new_crossings[@]} > 0 )); then
	for c in "${new_crossings[@]}"; do
		case "${c%:*}" in
			emergency)
				emergency_msg+=$'\n**EMERGENCY** Scaling Edgegap fleet to 0.'
				if [[ -n "${EDGEGAP_APP_NAME:-}" ]]; then
					curl -fsS -X PATCH \
						-H "Authorization: Token $EDGEGAP_TOKEN" \
						-H "Content-Type: application/json" \
						"https://api.edgegap.com/v1/app/$EDGEGAP_APP_NAME" \
						-d '{"capacity_max": 0}' >/dev/null || true
				fi
				;;
			r2_hard)
				# Active enforcement happens in
				# deploy-cf-pages.ps1, which queries this same
				# /usage endpoint before each upload. The alert
				# here just makes sure we notice.
				emergency_msg+=$'\n**R2 HARD CAP** Bucket is at the configured limit. New deploys will refuse to upload until you free space (or raise R2_HARD_GB).'
				;;
		esac
	done
fi

# ---------------------------------------------------------------------
# Discord routing.
# ---------------------------------------------------------------------
mention=""
if [[ -n "$DISCORD_USER_ID" ]]; then
	mention="<@${DISCORD_USER_ID}> "
fi

last_summary_day=$(echo "$state" | jq -r '.last_summary_day // ""')
should_summarize=0
if [[ "$CURRENT_HOUR_UTC" == "$DAILY_SUMMARY_HOUR_UTC" \
		&& "$last_summary_day" != "$CURRENT_DAY" ]]; then
	should_summarize=1
	state=$(echo "$state" | jq --arg d "$CURRENT_DAY" '.last_summary_day = $d')
fi

post_discord() {
	local content="$1"
	curl -fsS -X POST \
		-H "Content-Type: application/json" \
		-d "$(jq -n --arg c "$content" '{content:$c}')" \
		"$DISCORD_WEBHOOK_URL" >/dev/null
}

# Threshold crossings → immediate ping.
if (( ${#new_crossings[@]} > 0 )); then
	crossed_str=""
	for c in "${new_crossings[@]}"; do
		label="$(echo "${c%:*}" | tr 'a-z' 'A-Z' | tr '_' ' ')"
		crossed_str+="$label @ ${c#*:} | "
	done
	crossed_str="${crossed_str% | }"
	post_discord "${mention}**Threshold crossed: $crossed_str**
- AWS+Hetzner+Edgegap MTD: \$$total_usd ($CURRENT_MONTH)
- Hetzner: \$$hetzner_usd · Edgegap: \$$edgegap_usd
- R2 storage: ${r2_gb} GB / 10 GB free tier${emergency_msg}"
fi

# Daily summary.
if (( should_summarize )); then
	post_discord "**Daily cost: \$$total_usd MTD ($CURRENT_MONTH)**
- Hetzner: \$$hetzner_usd · Edgegap: \$$edgegap_usd
- R2 storage: ${r2_gb} GB / 10 GB free tier
- Thresholds — low \$$BUDGET_WARN_LOW · mid \$$BUDGET_WARN_MID · high \$$BUDGET_WARN_HIGH · emergency \$$EMERGENCY_CAP · R2 warn ${R2_WARN_GB:-8}GB · R2 hard ${R2_HARD_GB:-9.5}GB"
fi

# Persist state.
echo "$state" > "$STATE_FILE"

echo "[cost-monitor] $NOW_ISO total=\$$total_usd hetzner=\$$hetzner_usd edgegap=\$$edgegap_usd r2=${r2_gb}GB new_crossings=${new_crossings[*]:-none} summary=$should_summarize"
