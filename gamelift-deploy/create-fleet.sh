#!/usr/bin/env bash
# Create GameLift container fleet and supporting resources.
# Run this AFTER deploy.ps1 has pushed the container image.
#
# Usage: bash gamelift-deploy/create-fleet.sh
#
# Prerequisites:
#   - AWS CLI configured (aws sso login --profile hopnbop)
#   - Container group definition already created
#   - FlexMatch ruleset already created

set -euo pipefail

PROFILE="hopnbop"
REGION="us-west-2"
ACCOUNT_ID="270469481989"

echo "=== GameLift Fleet Setup ==="
echo ""

# Step 1: Create FlexMatch matchmaking ruleset.
echo "[1/4] Creating FlexMatch ruleset..."
MSYS_NO_PATHCONV=1 aws gamelift create-matchmaking-rule-set \
    --name hopnbop-ffa-ruleset \
    --rule-set-body file://gamelift-deploy/flexmatch-ruleset.json \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "  (ruleset may already exist)"

# Step 2: Create container fleet.
echo "[2/4] Creating container fleet..."
echo "  Note: Fleet creation takes 10-30 minutes."
MSYS_NO_PATHCONV=1 aws gamelift create-container-fleet \
    --fleet-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/GameLiftContainerFleetRole" \
    --description "Hop n Bop game server fleet" \
    --game-server-container-group-definition-name hopnbop-server-group \
    --instance-type c5.large \
    --instance-connection-port-range "FromPort=4433,ToPort=4434" \
    --region "$REGION" \
    --profile "$PROFILE" 2>&1

FLEET_ID=$(MSYS_NO_PATHCONV=1 aws gamelift list-fleets \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "FleetIds[0]" \
    --output text 2>/dev/null)

echo "  Fleet ID: $FLEET_ID"

# Step 3: Create game session queue.
echo "[3/4] Creating game session queue..."
MSYS_NO_PATHCONV=1 aws gamelift create-game-session-queue \
    --name hopnbop-game-queue \
    --destinations "DestinationArn=arn:aws:gamelift:${REGION}:${ACCOUNT_ID}:containerfleet/${FLEET_ID}" \
    --timeout-in-seconds 120 \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "  (queue may already exist)"

# Step 4: Create matchmaking configuration.
echo "[4/4] Creating matchmaking configuration..."
MSYS_NO_PATHCONV=1 aws gamelift create-matchmaking-configuration \
    --name hopnbop-ffa-matchmaker \
    --game-session-queue-arns "arn:aws:gamelift:${REGION}:${ACCOUNT_ID}:gamesessionqueue/hopnbop-game-queue" \
    --rule-set-name hopnbop-ffa-ruleset \
    --request-timeout-seconds 60 \
    --no-acceptance-required \
    --additional-player-count 0 \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "  (config may already exist)"

echo ""
echo "=== Fleet setup complete ==="
echo ""
echo "The fleet will take 10-30 minutes to reach ACTIVE state."
echo "Monitor with:"
echo "  aws gamelift describe-fleet-attributes --fleet-ids $FLEET_ID --region $REGION --profile $PROFILE"
