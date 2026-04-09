"""Patch webrtc-native to support portRangeBegin/End.

Inserts port range parsing into _initialize() so that
the libdatachannel ICE agent binds to a specific port
instead of an ephemeral one.
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
"""

src = SRC.read_text()
if MARKER not in src:
    print(f"ERROR: '{MARKER}' not found in {SRC}")
    sys.exit(1)

src = src.replace(MARKER, PATCH + "\t" + MARKER, 1)
SRC.write_text(src)
print("Patched _initialize with portRange support")
