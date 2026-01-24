# Building Jump 'n Thump with GameLift Support

This document describes how to build the GameLift GDExtension for Jump 'n Thump.

# FIXME: Review this.

## Prerequisites

### Required Tools
- **cmake** 3.16+ - Build system for GameLift SDK
- **SCons** 4.0+ - Build system for GDExtension (install via `pip install scons`)
- **make** - GNU Make
- **C++ Compiler**:
  - Linux: GCC 9+ or Clang 10+
  - Windows: WSL with Ubuntu recommended (MSVC has compatibility issues)
  - macOS: Xcode Command Line Tools
- **Git** - For cloning dependencies
- **Python 3** - For SCons

### Required SDKs

#### 1. Godot CPP Bindings
Clone godot-cpp into the gamelift-gdextension directory:

```bash
cd gamelift-gdextension
git clone --branch 4.5 https://github.com/godotengine/godot-cpp.git
cd godot-cpp
git submodule update --init
```

#### 2. AWS GameLift Server SDK

**Download:**
- Linux: https://aws.amazon.com/gamelift/getting-started/
- Windows: Same URL, different package

**Build GameLift SDK with std::string support:**

```bash
# Extract SDK to gamelift-gdextension/gamelift-server-sdk/
cd gamelift-server-sdk
mkdir build && cd build

# CRITICAL: Must use -DGAMELIFT_USE_STD=1 for C++ compatibility.
cmake .. -DGAMELIFT_USE_STD=1 -DCMAKE_BUILD_TYPE=Release

make -j$(nproc)
```

Expected output structure:
```
gamelift-server-sdk/
├── include/
│   └── aws/gamelift/server/...
└── lib/
    └── libaws-cpp-sdk-gamelift-server.so (or .dll on Windows)
```

#### 3. OpenSSL

**Linux:**
```bash
sudo apt-get install libssl-dev
```

**Windows:**
Download pre-compiled binaries from https://slproweb.com/products/Win32OpenSSL.html

**macOS:**
```bash
brew install openssl@3
```

## Building the Extension

### Automated Build (Recommended)

The easiest way to build is using the automated setup script:

```bash
cd gamelift-gdextension
./build.sh --godot-version 4.5
```

This script will:
1. Check prerequisites (cmake, make, scons, etc.)
2. Clone and build godot-cpp
3. Clone and build GameLift Server SDK (with `-DGAMELIFT_USE_STD=1`)
4. Build the GDExtension
5. Copy dependencies to bin/

### Quick Build (Linux Debug)
```bash
cd gamelift-gdextension
./build.sh --skip-deps --debug
```

### Platform-Specific Builds

**Windows (using WSL):**

The recommended approach for building on Windows is using WSL:

1. Install WSL and Ubuntu:
   ```powershell
   wsl --install -d Ubuntu
   ```

2. Install prerequisites in WSL:
   ```bash
   sudo apt-get update
   sudo apt-get install cmake make gcc g++ python3 libssl-dev
   pip3 install --user scons
   ```

3. Build from WSL:
   ```bash
   cd /mnt/c/Users/YourUser/Repositories/jumpnthump/gamelift-gdextension
   ./build.sh --godot-version 4.5
   ```

**Linux (for GameLift deployment):**
```bash
cd gamelift-gdextension
scons platform=linux target=template_release -j$(nproc)
scons install  # Copies to ../addons/gamelift/
```

**Manual Build (if setup script fails):**
```bash
# 1. Build GameLift SDK
cd gamelift-server-sdk
mkdir -p cmake-build && cd cmake-build
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DGAMELIFT_USE_STD=1 -DBUILD_FOR_UNREAL=ON -S .. -B .
make -j4

# 2. Build godot-cpp
cd ../../godot-cpp
scons platform=linux target=template_release -j4

# 3. Build GDExtension
cd ..
GAMELIFT_SDK_PATH=gamelift-server-sdk/cmake-build/prefix scons platform=linux target=template_release -j4

# 4. Install
scons install
cp gamelift-server-sdk/cmake-build/prefix/lib/libaws-cpp-sdk-gamelift-server.so ../addons/gamelift/bin/
```

### Environment Variables

If SDKs are not in default locations, set these before building:

```bash
export GODOT_CPP_PATH="/path/to/godot-cpp"
export GAMELIFT_SDK_PATH="/path/to/gamelift-server-sdk"
export OPENSSL_PATH="/path/to/openssl"

scons platform=linux target=template_release
```

## Runtime Dependencies

### Linux
The built extension requires GameLift SDK libraries at runtime:

```bash
# Option 1: System-wide installation
sudo cp gamelift-server-sdk/lib/*.so /usr/local/lib/
sudo ldconfig

# Option 2: Set LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/path/to/gamelift-server-sdk/lib:$LD_LIBRARY_PATH
godot --headless -- --server
```

### Windows
Place DLLs in the same directory as the Godot executable:
- `aws-cpp-sdk-gamelift-server.dll`
- `libssl-3-x64.dll`
- `libcrypto-3-x64.dll`

## Verifying the Build

Check that the extension is properly installed:

```bash
ls -la addons/gamelift/
# Should show:
# gamelift.gdextension
# bin/libgamelift.linux.template_debug.x86_64.so (or equivalent)
```

Open Godot and check for errors in the Output tab. If the extension loads successfully, you should see no error messages related to GameLift.

## Deployment to GameLift

### 1. Build for Linux Release
```bash
cd gamelift-gdextension
./build.sh --skip-deps --release
```

### 2. Export Godot Project
Use Godot's export dialog to create a Linux server build (headless, no visuals).

### 3. Create Deployment Package
```bash
# Create directory structure
mkdir -p gamelift-server-deploy/lib

# Copy server binary
cp exported_server gamelift-server-deploy/

# Copy GameLift extension
cp -r addons/gamelift gamelift-server-deploy/

# Copy GameLift SDK libraries
cp gamelift-server-sdk/lib/*.so gamelift-server-deploy/lib/

# Copy OpenSSL libraries
cp /usr/lib/x86_64-linux-gnu/libssl.so.3 gamelift-server-deploy/lib/
cp /usr/lib/x86_64-linux-gnu/libcrypto.so.3 gamelift-server-deploy/lib/

# Create install script
cat > gamelift-server-deploy/install.sh << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="$(pwd)/lib:$LD_LIBRARY_PATH"
chmod +x exported_server
EOF

chmod +x gamelift-server-deploy/install.sh

# Package
tar -czf gamelift-server-deploy.tar.gz gamelift-server-deploy/
```

### 4. Upload to GameLift
Use AWS CLI or GameLift console to upload the deployment package.

## Troubleshooting

### SCons version too old
**Error:** `SCons 4.0 or greater required, but you have SCons 3.1.2`

**Solution:**
```bash
pip3 install --user --upgrade scons
# Add ~/.local/bin to PATH if needed
export PATH=$HOME/.local/bin:$PATH
```

### "Text file busy" error during GameLift SDK build
This occurs when building on Windows filesystem (NTFS) from WSL.

**Solution:** Build with tests disabled:
```bash
cmake -DBUILD_FOR_UNREAL=ON  # This disables unit tests
```

### "libaws-cpp-sdk-gamelift-server.so: cannot open shared object file"
- Ensure GameLift SDK libraries are in LD_LIBRARY_PATH (Linux) or same directory as executable (Windows)
- Verify library file exists at expected location
- The library should be in `addons/gamelift/bin/`

### "undefined symbol" errors
- Rebuild GameLift SDK with `-DGAMELIFT_USE_STD=1` flag
- Ensure compiler versions match between SDK build and extension build

### Extension not loading in Godot
- Check Godot version matches godot-cpp branch (4.5)
- Verify gamelift.gdextension file is in addons/gamelift/
- Check Output tab in Godot for detailed error messages
- Ensure both `libgamelift.*.so` and `libaws-cpp-sdk-gamelift-server.so` are in `addons/gamelift/bin/`

### Build fails with "No such file or directory: godot-cpp"
- Ensure godot-cpp is cloned into gamelift-gdextension/godot-cpp/
- Run `git submodule update --init` inside godot-cpp directory

### AttributeValue compilation errors
**Error:** `'class Aws::GameLift::Server::Model::AttributeValue' has no member named 'SetN'`

**Cause:** GameLift SDK API changed - AttributeValue uses constructors instead of setters.

**Fixed in:** [gamelift_server.cpp:641](gamelift-gdextension/src/gamelift_server.cpp#L641)

## Development Workflow

For rapid iteration during development:

1. Make C++ changes in gamelift-gdextension/src/
2. Run `./build.sh --skip-deps --debug`
3. Restart Godot to reload the extension
4. Test changes

## Further Reading

- [GameLift Server SDK Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/integration-engines-setup-release.html)
- [Godot GDExtension Documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/index.html)
- [SCons Build System](https://scons.org/documentation.html)
