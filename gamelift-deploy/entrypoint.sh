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

    # Start nginx as a daemon. It terminates TLS on
    # port 4434 and proxies to the Godot WebSocket
    # server on localhost:4433.
    nginx
    echo "nginx started (WSS proxy on port 4434)."
else
    echo "WARNING: Could not fetch TLS cert. WSS will not be available."
    echo "ENet (native) connections on port 4433 are unaffected."
fi

# Start Godot server in the foreground. Using exec
# so the server process replaces the shell (health
# check uses pgrep -f hopnbop_server).
exec /game/hopnbop_server.x86_64 --server --headless \
    2>&1 | tee /game/logs/server.log
