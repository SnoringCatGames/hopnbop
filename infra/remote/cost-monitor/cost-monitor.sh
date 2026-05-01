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

# GitHub Actions usage tracking (org-level). Requires a token
# with `manage_billing:actions` scope (classic PAT) or fine-
# grained PAT with Plan:read access on the org. Without these,
# the GitHub block in this script is silently skipped.
GITHUB_ORG="${GITHUB_ORG:-snoringcatgames}"

CURRENT_MONTH="$(date -u +%Y-%m)"
CURRENT_DAY="$(date -u +%Y-%m-%d)"
CURRENT_HOUR_UTC="$(date -u +%-H)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"
MONTH_START_EPOCH="$(date -u -d "${CURRENT_MONTH}-01" +%s)"
MONTH_LABEL="$(date -u -d "${CURRENT_MONTH}-01" "+%B %Y")"

mkdir -p "$(dirname "$STATE_FILE")"

# ---------------------------------------------------------------------
# State
# ---------------------------------------------------------------------
state="{}"
if [[ -f "$STATE_FILE" ]]; then
	state=$(cat "$STATE_FILE")
fi
state_month=$(echo "$state" | jq -r '.month // ""')
# Carry the previous summary's total into a sticky field. The
# daily summary uses this to show day-over-day deltas so big
# jumps (server recreates, pricing-API blips, month rollover)
# are visible at a glance instead of looking like a fresh
# monthly start.
prev_summary_total_usd=$(echo "$state" | jq -r '.last_summary_total_usd // ""')
prev_month_total_usd=""
prev_month_label=""
if [[ "$state_month" != "$CURRENT_MONTH" ]]; then
	# Capture the just-closed month's last-known total before
	# resetting state. Stored in `prev_month_*` and surfaced on
	# the first daily summary of the new month.
	if [[ -n "$state_month" ]]; then
		prev_month_total_usd="$prev_summary_total_usd"
		prev_month_label="$(date -u -d "${state_month}-01" "+%B %Y" 2>/dev/null || echo "$state_month")"
	fi
	state=$(jq -n \
		--arg m "$CURRENT_MONTH" \
		--arg pmt "$prev_month_total_usd" \
		--arg pml "$prev_month_label" \
		'{
			month: $m,
			thresholds_crossed: [],
			last_summary_day: "",
			last_summary_total_usd: "",
			prev_month_total_usd: $pmt,
			prev_month_label: $pml
		}')
	# After reset, prev_summary_total_usd is no longer meaningful
	# for day-over-day comparison (different month).
	prev_summary_total_usd=""
fi
# The first summary after a rollover surfaces the carried-over
# values; later summaries within the same month don't need them.
carry_prev_month_total_usd=$(echo "$state" | jq -r '.prev_month_total_usd // ""')
carry_prev_month_label=$(echo "$state" | jq -r '.prev_month_label // ""')

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
# GitHub Actions billing for the org. Two endpoints:
#   /orgs/{org}/settings/billing/actions       — minutes used + paid
#   /orgs/{org}/settings/billing/shared-storage — storage GB + paid
# Both require a token scoped to org plan/billing reads. If the
# token lacks scope or the call fails, the block is skipped and
# `gh_tracked` stays false; messages omit the GH line entirely.
# ---------------------------------------------------------------------
gh_tracked=false
gh_minutes_used=0
gh_minutes_included=0
gh_minutes_paid=0
gh_storage_estimated_gb=0
gh_storage_paid_gb=0
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_ORG:-}" ]]; then
	if actions_resp=$(curl -fsS \
			-H "Authorization: Bearer $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github+json" \
			"https://api.github.com/orgs/$GITHUB_ORG/settings/billing/actions" 2>/dev/null); then
		gh_minutes_used=$(echo "$actions_resp" | jq -r '.total_minutes_used // 0')
		gh_minutes_included=$(echo "$actions_resp" | jq -r '.included_minutes // 0')
		gh_minutes_paid=$(echo "$actions_resp" | jq -r '.total_paid_minutes_used // 0')
		gh_tracked=true
	fi
	if storage_resp=$(curl -fsS \
			-H "Authorization: Bearer $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github+json" \
			"https://api.github.com/orgs/$GITHUB_ORG/settings/billing/shared-storage" 2>/dev/null); then
		gh_storage_estimated_gb=$(echo "$storage_resp" | jq -r '.estimated_storage_for_month // 0')
		gh_storage_paid_gb=$(echo "$storage_resp" | jq -r '.estimated_paid_storage_for_month // 0')
		gh_tracked=true
	fi
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

# GitHub overage thresholds. We treat any nonzero paid usage
# (minutes or storage) as a crossing — the org should sit
# entirely inside the included free quota during normal
# operation. State key gets reset with the rest on month
# rollover.
if $gh_tracked; then
	if awk -v m="$gh_minutes_paid" 'BEGIN { exit !(m > 0) }'; then
		if ! echo "$already_crossed" | grep -qx "gh_actions_paid"; then
			new_crossings+=("gh_actions_paid:${gh_minutes_paid}min")
			state=$(echo "$state" | jq \
				'.thresholds_crossed += ["gh_actions_paid"]')
		fi
	fi
	if awk -v g="$gh_storage_paid_gb" 'BEGIN { exit !(g > 0) }'; then
		if ! echo "$already_crossed" | grep -qx "gh_storage_paid"; then
			new_crossings+=("gh_storage_paid:${gh_storage_paid_gb}GB")
			state=$(echo "$state" | jq \
				'.thresholds_crossed += ["gh_storage_paid"]')
		fi
	fi
fi

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

# Common body lines shared between threshold-crossing and daily
# summary messages. Each tracked provider gets its own line so
# adding more later doesn't bunch up the formatting.
provider_lines="- Hetzner: \$$hetzner_usd
- Edgegap: \$$edgegap_usd
- R2 storage: ${r2_gb} GB / 10 GB free tier"
if $gh_tracked; then
	provider_lines+="
- GH Actions: ${gh_minutes_used} / ${gh_minutes_included} min · ${gh_storage_estimated_gb} GB shared storage"
	# Only call out paid-tier usage if there is any. Keeps the
	# happy-path summary terse.
	if awk -v m="$gh_minutes_paid" -v g="$gh_storage_paid_gb" \
			'BEGIN { exit !(m > 0 || g > 0) }'; then
		provider_lines+=" (paid: ${gh_minutes_paid} min · ${gh_storage_paid_gb} GB)"
	fi
fi

# Day-over-day delta annotation. Empty unless we have a previous
# summary's total to compare against (skipped on the very first
# summary or right after a month rollover).
delta_line=""
if [[ -n "$prev_summary_total_usd" ]]; then
	delta_line=" (was \$$prev_summary_total_usd at last summary)"
fi

# First summary of a new month carries the closing total of the
# previous month forward, so the headline drop from rollover
# doesn't look mysterious.
prev_month_line=""
if [[ -n "$carry_prev_month_total_usd" \
		&& -n "$carry_prev_month_label" ]]; then
	prev_month_line=$'\n'"$carry_prev_month_label closed at \$$carry_prev_month_total_usd"
fi

# Threshold crossings → immediate ping.
if (( ${#new_crossings[@]} > 0 )); then
	crossed_str=""
	for c in "${new_crossings[@]}"; do
		label="$(echo "${c%:*}" | tr 'a-z' 'A-Z' | tr '_' ' ')"
		crossed_str+="$label @ ${c#*:} | "
	done
	crossed_str="${crossed_str% | }"
	post_discord "${mention}**Threshold crossed: $crossed_str**
- Hetzner+Edgegap MTD: \$$total_usd ($MONTH_LABEL)
$provider_lines${emergency_msg}"
fi

# Daily summary.
if (( should_summarize )); then
	post_discord "**Billing status — $MONTH_LABEL: \$$total_usd MTD$delta_line**$prev_month_line
$provider_lines
- Thresholds — low \$$BUDGET_WARN_LOW · mid \$$BUDGET_WARN_MID · high \$$BUDGET_WARN_HIGH · emergency \$$EMERGENCY_CAP · R2 warn ${R2_WARN_GB:-8}GB · R2 hard ${R2_HARD_GB:-9.5}GB"
	# Capture this summary's headline number so the next
	# summary can show a day-over-day delta. Also clear the
	# carry-forward fields once they've been displayed.
	state=$(echo "$state" | jq \
		--arg t "$total_usd" \
		'.last_summary_total_usd = $t
		| .prev_month_total_usd = ""
		| .prev_month_label = ""')
fi

# Persist state.
echo "$state" > "$STATE_FILE"

echo "[cost-monitor] $NOW_ISO total=\$$total_usd hetzner=\$$hetzner_usd edgegap=\$$edgegap_usd r2=${r2_gb}GB gh_min=${gh_minutes_used}/${gh_minutes_included} gh_paid_min=${gh_minutes_paid} gh_storage_gb=${gh_storage_estimated_gb} new_crossings=${new_crossings[*]:-none} summary=$should_summarize"
