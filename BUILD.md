# Building Jump 'n Thump with GameLift Support

This document describes how to build the GameLift GDExtension for Jump 'n Thump.

# FIXME: Review this.

## Prerequisites

### Required Tools
- **SCons** - Build system (install via `pip install scons`)
- **C++ Compiler**:
  - Linux: GCC 9+ or Clang 10+
  - Windows: MSVC 2019+ or MinGW-w64
  - macOS: Xcode Command Line Tools
- **Git** - For cloning dependencies

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

### Quick Build (Linux Debug)
```bash
cd gamelift-gdextension
./build_and_install.sh linux template_debug
```

### Platform-Specific Builds

**Linux (for GameLift deployment):**
```bash
cd gamelift-gdextension
scons platform=linux target=template_release -j$(nproc)
scons install  # Copies to ../addons/gamelift/
```

**Windows (for local testing):**
```bash
cd gamelift-gdextension
scons platform=windows target=template_debug
scons install
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
./build_and_install.sh linux template_release
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

### "libaws-cpp-sdk-gamelift-server.so: cannot open shared object file"
- Ensure GameLift SDK libraries are in LD_LIBRARY_PATH (Linux) or same directory as executable (Windows)
- Verify library file exists at expected location

### "undefined symbol" errors
- Rebuild GameLift SDK with `-DGAMELIFT_USE_STD=1` flag
- Ensure compiler versions match between SDK build and extension build

### Extension not loading in Godot
- Check Godot version matches godot-cpp branch (4.5)
- Verify gamelift.gdextension file is in addons/gamelift/
- Check Output tab in Godot for detailed error messages

### Build fails with "No such file or directory: godot-cpp"
- Ensure godot-cpp is cloned into gamelift-gdextension/godot-cpp/
- Run `git submodule update --init` inside godot-cpp directory

## Development Workflow

For rapid iteration during development:

1. Make C++ changes in gamelift-gdextension/src/
2. Run `./build_and_install.sh linux template_debug`
3. Restart Godot to reload the extension
4. Test changes

## Further Reading

- [GameLift Server SDK Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/integration-engines-setup-release.html)
- [Godot GDExtension Documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/index.html)
- [SCons Build System](https://scons.org/documentation.html)
