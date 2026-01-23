#!/bin/bash
# setup_and_build.sh - Set up dependencies and build the GameLift GDExtension
#
# Usage:
#   ./setup_and_build.sh [--godot-version 4.2] [--skip-deps] [--debug]

set -e

# =============================================================================
# Configuration
# =============================================================================

GODOT_VERSION="4.2-stable"
BUILD_TYPE="template_release"
SKIP_DEPS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --godot-version)
            GODOT_VERSION="$2"
            shift 2
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --debug)
            BUILD_TYPE="template_debug"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --godot-version VERSION  Godot version branch (default: 4.2-stable)"
            echo "  --skip-deps              Skip downloading dependencies"
            echo "  --debug                  Build debug version instead of release"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=============================================="
echo "GameLift GDExtension Build Script"
echo "=============================================="
echo "Godot Version: $GODOT_VERSION"
echo "Build Type: $BUILD_TYPE"
echo "Script Directory: $SCRIPT_DIR"
echo ""

# =============================================================================
# Check Prerequisites
# =============================================================================

echo "[1/6] Checking prerequisites..."

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "ERROR: $1 is required but not installed."
        exit 1
    fi
    echo "  ✓ $1 found"
}

check_command git
check_command cmake
check_command make
check_command python3
check_command scons

# Check for OpenSSL development headers
if [ ! -f /usr/include/openssl/ssl.h ] && [ ! -f /usr/local/include/openssl/ssl.h ]; then
    echo "WARNING: OpenSSL development headers not found."
    echo "         Install with: sudo apt-get install libssl-dev"
fi

echo ""

# =============================================================================
# Clone/Update godot-cpp
# =============================================================================

if [ "$SKIP_DEPS" = false ]; then
    echo "[2/6] Setting up godot-cpp..."
    
    if [ -d "$SCRIPT_DIR/godot-cpp" ]; then
        echo "  godot-cpp directory exists, updating..."
        cd "$SCRIPT_DIR/godot-cpp"
        git fetch origin
        git checkout "godot-$GODOT_VERSION" || git checkout "$GODOT_VERSION"
        git submodule update --init --recursive
    else
        echo "  Cloning godot-cpp..."
        git clone --recurse-submodules https://github.com/godotengine/godot-cpp.git "$SCRIPT_DIR/godot-cpp"
        cd "$SCRIPT_DIR/godot-cpp"
        git checkout "godot-$GODOT_VERSION" || git checkout "$GODOT_VERSION"
    fi
    
    cd "$SCRIPT_DIR"
    echo "  ✓ godot-cpp ready"
else
    echo "[2/6] Skipping godot-cpp setup (--skip-deps)"
fi

echo ""

# =============================================================================
# Clone/Build GameLift Server SDK
# =============================================================================

if [ "$SKIP_DEPS" = false ]; then
    echo "[3/6] Setting up GameLift Server SDK..."
    
    if [ -d "$SCRIPT_DIR/gamelift-server-sdk" ]; then
        echo "  GameLift SDK directory exists, updating..."
        cd "$SCRIPT_DIR/gamelift-server-sdk"
        git pull origin main || true
    else
        echo "  Cloning GameLift Server SDK..."
        git clone https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk.git "$SCRIPT_DIR/gamelift-server-sdk"
    fi
    
    cd "$SCRIPT_DIR/gamelift-server-sdk"
    
    echo "  Building GameLift SDK..."
    mkdir -p cmake-build
    cd cmake-build
    
    cmake -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGAMELIFT_USE_STD=1 \
        -S .. -B .
    
    make -j$(nproc)
    
    cd "$SCRIPT_DIR"
    echo "  ✓ GameLift SDK built"
else
    echo "[3/6] Skipping GameLift SDK setup (--skip-deps)"
fi

echo ""

# =============================================================================
# Build godot-cpp bindings
# =============================================================================

echo "[4/6] Building godot-cpp bindings..."

cd "$SCRIPT_DIR/godot-cpp"

# Build godot-cpp for the target
scons platform=linux target="$BUILD_TYPE" -j$(nproc)

cd "$SCRIPT_DIR"
echo "  ✓ godot-cpp bindings built"

echo ""

# =============================================================================
# Build GDExtension
# =============================================================================

echo "[5/6] Building GameLift GDExtension..."

cd "$SCRIPT_DIR"

# Set up environment variables
export GODOT_CPP_PATH="$SCRIPT_DIR/godot-cpp"
export GAMELIFT_SDK_PATH="$SCRIPT_DIR/gamelift-server-sdk/cmake-build"
export OPENSSL_PATH="/usr"

# Create bin directory
mkdir -p bin

# Build the extension
scons platform=linux target="$BUILD_TYPE" -j$(nproc)

echo "  ✓ GDExtension built"

echo ""

# =============================================================================
# Copy Dependencies
# =============================================================================

echo "[6/6] Copying dependencies to bin/..."

# Copy GameLift SDK library
if [ -f "$GAMELIFT_SDK_PATH/libaws-cpp-sdk-gamelift-server.so" ]; then
    cp "$GAMELIFT_SDK_PATH/libaws-cpp-sdk-gamelift-server.so" "$SCRIPT_DIR/bin/"
    echo "  ✓ Copied libaws-cpp-sdk-gamelift-server.so"
fi

# Try to find and copy OpenSSL libraries
OPENSSL_LIB_PATHS=(
    "/usr/lib/x86_64-linux-gnu"
    "/usr/lib64"
    "/usr/local/lib"
    "/lib/x86_64-linux-gnu"
)

for lib_path in "${OPENSSL_LIB_PATHS[@]}"; do
    if [ -f "$lib_path/libssl.so.3" ]; then
        cp "$lib_path/libssl.so.3" "$SCRIPT_DIR/bin/"
        cp "$lib_path/libcrypto.so.3" "$SCRIPT_DIR/bin/"
        echo "  ✓ Copied OpenSSL libraries from $lib_path"
        break
    fi
done

echo ""

# =============================================================================
# Summary
# =============================================================================

echo "=============================================="
echo "Build Complete!"
echo "=============================================="
echo ""
echo "Output files in: $SCRIPT_DIR/bin/"
ls -la "$SCRIPT_DIR/bin/"
echo ""
echo "To use in your Godot project:"
echo "  1. Create: your_project/addons/gamelift/"
echo "  2. Copy gamelift.gdextension to addons/gamelift/"
echo "  3. Copy bin/ folder to addons/gamelift/"
echo ""
echo "Example:"
echo "  mkdir -p your_project/addons/gamelift"
echo "  cp gamelift.gdextension your_project/addons/gamelift/"
echo "  cp -r bin your_project/addons/gamelift/"
echo ""
