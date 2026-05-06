"""Patch webrtc-native to support portRange and UDP mux.

Inserts port range and ICE UDP mux parsing into
_initialize() so that:
1. The ICE agent binds to a specific port instead
   of an ephemeral one.
2. Multiple PeerConnections share the same UDP
   socket via libjuice's mux mode (required for
   multi-client WebRTC on a single port).
"""
import pathlib
import sys

SRC = pathlib.Path("src/WebRTCLibPeerConnection.cpp")
MARKER = "return _create_pc(config);"
PATCH = """\
\tif (p_config.has("portRangeBegin")) {
\t\tconfig.portRangeBegin = (uint16_t)(int)p_config["portRangeBegin"];
\t}
\tif (p_config.has("portRangeEnd")) {
\t\tconfig.portRangeEnd = (uint16_t)(int)p_config["portRangeEnd"];
\t}
\tif (p_config.has("enableIceUdpMux")) {
\t\tconfig.enableIceUdpMux = (bool)p_config["enableIceUdpMux"];
\t}
"""

src = SRC.read_text()
if MARKER not in src:
    print(f"ERROR: '{MARKER}' not found in {SRC}")
    sys.exit(1)

src = src.replace(MARKER, PATCH + "\t" + MARKER, 1)
SRC.write_text(src)
print("Patched _initialize with portRange + mux support")
