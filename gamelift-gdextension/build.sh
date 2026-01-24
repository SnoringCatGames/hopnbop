#!/bin/bash
# build.sh - Set up dependencies and build the GameLift GDExtension
#
# Usage:
#   ./build.sh [options]

set -e

# =============================================================================
# Configuration
# =============================================================================

GODOT_VERSION="4.2-stable"
BUILD_TYPE="template_release"
SKIP_DEPS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_ADDONS_DIR="../addons/gamelift"
BUILD_PLATFORMS=()
BUILD_BOTH_CONFIGS=false

# Detect current OS
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "linux"  # WSL is still Linux for building
            else
                echo "linux"
            fi
            ;;
        Darwin*)
            echo "macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

CURRENT_OS=$(detect_os)

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
        --release)
            BUILD_TYPE="template_release"
            shift
            ;;
        --both)
            BUILD_BOTH_CONFIGS=true
            shift
            ;;
        --platform)
            BUILD_PLATFORMS+=("$2")
            shift 2
            ;;
        --all-platforms)
            BUILD_PLATFORMS=("linux" "windows" "macos")
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --godot-version VERSION  Godot version branch (default: 4.2-stable)"
            echo "  --skip-deps              Skip downloading dependencies"
            echo "  --debug                  Build debug version (default: release)"
            echo "  --release                Build release version"
            echo "  --both                   Build both debug and release"
            echo "  --platform PLATFORM      Build for specific platform (linux/windows/macos)"
            echo "                           Can be specified multiple times"
            echo "  --all-platforms          Build for all platforms"
            echo "  --help                   Show this help message"
            echo ""
            echo "Current OS: $CURRENT_OS"
            echo ""
            echo "Examples:"
            echo "  $0                              # Build for current OS ($CURRENT_OS)"
            echo "  $0 --platform linux --both      # Build debug+release for Linux"
            echo "  $0 --all-platforms --release    # Build release for all platforms"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If no platforms specified, use current OS
if [ ${#BUILD_PLATFORMS[@]} -eq 0 ]; then
    BUILD_PLATFORMS=("$CURRENT_OS")
fi

# Determine build configurations
BUILD_CONFIGS=("$BUILD_TYPE")
if [ "$BUILD_BOTH_CONFIGS" = true ]; then
    BUILD_CONFIGS=("template_release" "template_debug")
fi

echo "=============================================="
echo "GameLift GDExtension Build Script"
echo "=============================================="
echo "Current OS: $CURRENT_OS"
echo "Godot Version: $GODOT_VERSION"
echo "Build Configs: ${BUILD_CONFIGS[*]}"
echo "Target Platforms: ${BUILD_PLATFORMS[*]}"
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
        -DBUILD_FOR_UNREAL=ON \
        -S .. -B .

    make -j$(nproc)
    make install

    cd "$SCRIPT_DIR"
    echo "  ✓ GameLift SDK built and installed"
else
    echo "[3/6] Skipping GameLift SDK setup (--skip-deps)"
fi

echo ""

# =============================================================================
# Build godot-cpp bindings
# =============================================================================

echo "[4/6] Building godot-cpp bindings..."

cd "$SCRIPT_DIR/godot-cpp"

# Build godot-cpp for each platform and config
for platform in "${BUILD_PLATFORMS[@]}"; do
    for config in "${BUILD_CONFIGS[@]}"; do
        echo "  Building godot-cpp for $platform ($config)..."
        scons platform="$platform" target="$config" -j$(nproc) 2>&1 | tail -5
    done
done

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
# Fix: Use prefix subdirectory where CMake installs headers and libs
export GAMELIFT_SDK_PATH="$SCRIPT_DIR/gamelift-server-sdk/cmake-build/prefix"
export OPENSSL_PATH="/usr"

# Create bin directory
mkdir -p bin

# Build the extension for each platform and config
for platform in "${BUILD_PLATFORMS[@]}"; do
    for config in "${BUILD_CONFIGS[@]}"; do
        echo "  Building GDExtension for $platform ($config)..."

        # Platform-specific environment adjustments
        case "$platform" in
            linux)
                export OPENSSL_PATH="/usr"
                ;;
            macos)
                # Try Homebrew paths
                if [ -d "/opt/homebrew/opt/openssl@3" ]; then
                    export OPENSSL_PATH="/opt/homebrew/opt/openssl@3"
                elif [ -d "/usr/local/opt/openssl@3" ]; then
                    export OPENSSL_PATH="/usr/local/opt/openssl@3"
                fi
                ;;
            windows)
                # Windows builds need vcpkg or similar
                if [ -z "$OPENSSL_PATH" ]; then
                    echo "  WARNING: For Windows builds, set OPENSSL_PATH to vcpkg OpenSSL installation"
                fi
                ;;
        esac

        scons platform="$platform" target="$config" -j$(nproc) 2>&1 | tail -10
    done
done

echo "  ✓ GDExtension built"

echo ""

# =============================================================================
# Copy Dependencies
# =============================================================================

echo "[6/6] Copying dependencies to bin/..."

# Copy dependencies for each built platform
for platform in "${BUILD_PLATFORMS[@]}"; do
    echo "  Copying dependencies for $platform..."

    case "$platform" in
        linux)
            # Copy GameLift SDK library
            if [ -f "$GAMELIFT_SDK_PATH/lib/libaws-cpp-sdk-gamelift-server.so" ]; then
                cp "$GAMELIFT_SDK_PATH/lib/libaws-cpp-sdk-gamelift-server.so" "$SCRIPT_DIR/bin/"
                echo "    ✓ Copied libaws-cpp-sdk-gamelift-server.so"
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
                    cp "$lib_path/libssl.so.3" "$SCRIPT_DIR/bin/" 2>/dev/null || true
                    cp "$lib_path/libcrypto.so.3" "$SCRIPT_DIR/bin/" 2>/dev/null || true
                    echo "    ✓ Copied OpenSSL libraries from $lib_path"
                    break
                fi
            done
            ;;

        macos)
            # For macOS, dependencies are typically handled differently
            # GameLift SDK would be .dylib
            if [ -f "$GAMELIFT_SDK_PATH/lib/libaws-cpp-sdk-gamelift-server.dylib" ]; then
                cp "$GAMELIFT_SDK_PATH/lib/libaws-cpp-sdk-gamelift-server.dylib" "$SCRIPT_DIR/bin/" 2>/dev/null || true
                echo "    ✓ Copied libaws-cpp-sdk-gamelift-server.dylib"
            fi
            echo "    Note: macOS builds typically use system or Homebrew OpenSSL"
            ;;

        windows)
            # Windows DLLs
            if [ -f "$GAMELIFT_SDK_PATH/bin/aws-cpp-sdk-gamelift-server.dll" ]; then
                cp "$GAMELIFT_SDK_PATH/bin/aws-cpp-sdk-gamelift-server.dll" "$SCRIPT_DIR/bin/" 2>/dev/null || true
                echo "    ✓ Copied aws-cpp-sdk-gamelift-server.dll"
            fi

            # OpenSSL DLLs (if using vcpkg)
            if [ -n "$OPENSSL_PATH" ] && [ -d "$OPENSSL_PATH/bin" ]; then
                cp "$OPENSSL_PATH/bin/libssl-3-x64.dll" "$SCRIPT_DIR/bin/" 2>/dev/null || true
                cp "$OPENSSL_PATH/bin/libcrypto-3-x64.dll" "$SCRIPT_DIR/bin/" 2>/dev/null || true
                echo "    ✓ Copied OpenSSL DLLs"
            else
                echo "    WARNING: OpenSSL DLLs not found. Set OPENSSL_PATH for Windows builds."
            fi
            ;;
    esac
done

echo ""

# =============================================================================
# Install
# =============================================================================

echo ""
echo "Installing to $GODOT_ADDONS_DIR..."
mkdir -p "$GODOT_ADDONS_DIR/bin"

# Copy extension configuration
cp gamelift.gdextension "$GODOT_ADDONS_DIR/"

# Copy built binaries
if [ -d "bin" ]; then
    cp bin/* "$GODOT_ADDONS_DIR/bin/" 2>/dev/null || true
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================="
echo "Build and install complete!"
echo "========================================="
echo ""
echo "Built for platforms: ${BUILD_PLATFORMS[*]}"
echo "Built configurations: ${BUILD_CONFIGS[*]}"
echo ""
echo "Output files in: $SCRIPT_DIR/bin/"
ls -lh "$SCRIPT_DIR/bin/" 2>/dev/null | grep -E "\.(so|dll|dylib|framework)$" || echo "  (no libraries found)"
echo ""
echo "Installed to: $GODOT_ADDONS_DIR/"
echo ""
echo "Next steps:"
echo "1. Ensure GameLift Server SDK libraries are available at runtime"
echo "2. For Linux: LD_LIBRARY_PATH should include GameLift SDK lib directory"
echo "3. For Windows: Place GameLift SDK DLLs in same directory as executable"
echo "4. For macOS: Frameworks should be in the correct bundle location"
echo ""
echo "Cross-compilation notes:"
echo "  - Linux to Windows: Requires MinGW-w64 (install: apt-get install mingw-w64)"
echo "  - Linux to macOS: Generally requires macOS SDK and osxcross"
echo "  - Native builds are recommended for best compatibility"
echo ""
