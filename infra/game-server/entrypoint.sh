#!/bin/bash
# Game-server entrypoint for Edgegap deployments. Just exec's
# the Godot Linux server. Godot binds 4433/UDP for ENet game
# data and 4434/TCP for WebRTC signaling (via SIGNALING_PORT
# env from the runtime hook); the signaling-proxy on the
# platform host fronts wss:// and bridges plain ws:// in to
# that port.
#
# Server registration with the Nakama runtime
# (register_server RPC) happens from Godot AFTER the WS port
# is bound — see EdgegapServerProvider.register_with_runtime().
# That's the readiness signal the matchmaker hook waits on
# before sending match_ready notifications.
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
set -euo pipefail

exec /game/hopnbop_server.x86_64 \
	--headless \
	-- --server
