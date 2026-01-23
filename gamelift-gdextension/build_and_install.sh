#!/bin/bash
#
# Build and install GameLift GDExtension
#
# Usage:
#   ./build_and_install.sh [platform] [target]
#
# Examples:
#   ./build_and_install.sh linux template_debug
#   ./build_and_install.sh windows template_release
#

set -e

PLATFORM=${1:-linux}
TARGET=${2:-template_debug}
GODOT_ADDONS="../addons/gamelift"

echo "========================================="
echo "GameLift GDExtension Build and Install"
echo "========================================="
echo "Platform: $PLATFORM"
echo "Target:   $TARGET"
echo ""

# Build
echo "Building..."
scons platform=$PLATFORM target=$TARGET -j$(nproc 2>/dev/null || echo 4)

# Install
echo ""
echo "Installing to $GODOT_ADDONS..."
mkdir -p "$GODOT_ADDONS/bin"

# Copy extension configuration
cp gamelift.gdextension "$GODOT_ADDONS/"

# Copy built binaries
if [ -d "bin" ]; then
    cp bin/* "$GODOT_ADDONS/bin/" 2>/dev/null || true
fi

echo ""
echo "========================================="
echo "Build and install complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Ensure GameLift Server SDK libraries are available at runtime"
echo "2. For Linux: LD_LIBRARY_PATH should include GameLift SDK lib directory"
echo "3. For Windows: Place GameLift SDK DLLs in same directory as executable"
echo ""
