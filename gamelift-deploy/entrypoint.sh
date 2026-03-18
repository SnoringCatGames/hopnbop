#!/bin/bash
set -e

CERT_DIR="/game/tls"
mkdir -p "$CERT_DIR"

# Fetch TLS certificate from Secrets Manager.
# The wildcard cert for *.game.hopnbop.net enables
# WSS connections from web clients served over HTTPS.
echo "Fetching TLS certificate from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "hopnbop/tls-wildcard-cert" \
    --region us-west-2 \
    --query "SecretString" \
    --output text 2>/dev/null || true)

if [ -n "$SECRET_JSON" ]; then
    echo "$SECRET_JSON" | jq -r '.certificate' \
        > "$CERT_DIR/fullchain.pem"
    echo "$SECRET_JSON" | jq -r '.private_key' \
        > "$CERT_DIR/privkey.pem"
    chmod 600 "$CERT_DIR/privkey.pem"
    echo "TLS certificate loaded."

    # Start nginx for TLS detection and proxying.
    # Port 4434: stream listener with ssl_preread.
    #   - TLS (web wss://) -> 4435 (SSL terminate) -> Godot 4433.
    #   - Plain (native ws://) -> Godot 4433 directly.
    nginx
    echo "nginx started (TLS detection on port 4434)."
else
    echo "WARNING: Could not fetch TLS cert. WSS will not be available."
    echo "Plain ws:// and ENet connections are unaffected."
fi

# Pre-create DNS A record for this server instance.
# The hostname is derived deterministically from the
# public IP (e.g., s-35-91-191-229.game.hopnbop.net).
# By creating it at startup (minutes before any match),
# DNS is fully propagated by the time clients connect.
HOSTED_ZONE_ID="Z05562172A1JF6AX39U2N"
GAME_DOMAIN="game.hopnbop.net"

# Get public IP via EC2 instance metadata (IMDSv2).
IMDS_TOKEN=$(curl -s -X PUT \
    "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    --max-time 3 2>/dev/null || true)
if [ -n "$IMDS_TOKEN" ]; then
    PUBLIC_IP=$(curl -s \
        -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        "http://169.254.169.254/latest/meta-data/public-ipv4" \
        --max-time 3 2>/dev/null || true)
fi

# Fallback: external IP service.
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 \
        https://checkip.amazonaws.com 2>/dev/null \
        | tr -d '[:space:]' || true)
fi

if [ -n "$PUBLIC_IP" ]; then
    # Derive hostname from IP: 35.91.191.229 -> s-35-91-191-229
    IP_LABEL="s-$(echo "$PUBLIC_IP" | tr '.' '-')"
    HOSTNAME="${IP_LABEL}.${GAME_DOMAIN}"

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "{
            \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$HOSTNAME\",
                    \"Type\": \"A\",
                    \"TTL\": 30,
                    \"ResourceRecords\": [{\"Value\": \"$PUBLIC_IP\"}]
                }
            }]
        }" --region us-west-2 > /dev/null 2>&1 && \
        echo "DNS record created: $HOSTNAME -> $PUBLIC_IP" || \
        echo "WARNING: Failed to create DNS record for $HOSTNAME"
else
    echo "WARNING: Could not determine public IP. DNS record not created."
fi

# Start Godot server in the foreground. Using exec
# so the server process replaces the shell (health
# check uses pgrep -f hopnbop_server).
exec /game/hopnbop_server.x86_64 --server --headless \
    2>&1 | tee /game/logs/server.log
