# Building GameLift GDExtension

This document explains how to build the GameLift GDExtension for all platforms.

## Using GitHub Actions (Recommended)

The easiest way to build for all platforms is to use the GitHub Actions workflow.

### Automatic Builds

The workflow automatically runs when:
- You push changes to `gamelift-gdextension/` directory on `main` or `develop` branches
- You create a pull request affecting the extension
- You manually trigger it via "Actions" tab → "Build GameLift GDExtension" → "Run workflow"

### Downloading Built Libraries

1. Go to the **Actions** tab in your GitHub repository
2. Click on the latest **"Build GameLift GDExtension"** workflow run
3. Scroll down to **Artifacts**
4. Download **gamelift-gdextension-all-platforms.zip**
5. Extract the zip file
6. The extracted `addons/gamelift/` folder is ready to use in your Godot project

The artifact includes:
```
addons/gamelift/
├── gamelift.gdextension
└── bin/
    ├── libgamelift.linux.template_release.x86_64.so
    ├── libgamelift.linux.template_debug.x86_64.so
    ├── libgamelift.windows.template_release.x86_64.dll
    ├── libgamelift.windows.template_debug.x86_64.dll
    ├── libgamelift.macos.template_release.framework/
    ├── libgamelift.macos.template_debug.framework/
    ├── libaws-cpp-sdk-gamelift-server.so (Linux)
    ├── aws-cpp-sdk-gamelift-server.dll (Windows)
    ├── libssl.so.3 (Linux)
    ├── libcrypto.so.3 (Linux)
    ├── libssl-3-x64.dll (Windows)
    └── libcrypto-3-x64.dll (Windows)
```

### Platform-Specific Artifacts

If you only need one platform, you can download individual artifacts:
- `gamelift-gdextension-linux` - Linux binaries only
- `gamelift-gdextension-windows` - Windows binaries only
- `gamelift-gdextension-macos` - macOS binaries only

## Local Building

If you prefer to build locally, follow the platform-specific instructions below.

### Linux

```bash
cd gamelift-gdextension

# Run the automated setup script
./setup_and_build.sh

# Or build manually for both debug and release
./build_and_install.sh linux template_debug
./build_and_install.sh linux template_release
```

The script will:
1. Check for required tools (git, cmake, make, scons)
2. Clone and build godot-cpp
3. Clone and build AWS GameLift Server SDK
4. Build the GDExtension
5. Copy dependencies to `bin/`
6. Install to `../addons/gamelift/`

### Windows

Prerequisites:
- Visual Studio 2022 with C++ tools
- Python 3.x
- Git
- CMake

```powershell
# Install SCons
pip install scons

# Install vcpkg for OpenSSL
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
.\vcpkg install openssl:x64-windows
cd ..

# Clone godot-cpp
cd gamelift-gdextension
git clone --recurse-submodules https://github.com/godotengine/godot-cpp.git
cd godot-cpp
git checkout godot-4.2-stable

# Build godot-cpp
scons platform=windows target=template_release
scons platform=windows target=template_debug
cd ..

# Clone GameLift SDK
git clone https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk.git gamelift-server-sdk
cd gamelift-server-sdk
mkdir cmake-build
cd cmake-build

# Build GameLift SDK
cmake -G "Visual Studio 17 2022" -A x64 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DGAMELIFT_USE_STD=1 ^
  -DBUILD_FOR_UNREAL=ON ^
  -DOPENSSL_ROOT_DIR=path\to\vcpkg\installed\x64-windows ^
  -S .. -B .
cmake --build . --config Release
cd ..\..

# Build GDExtension
set GODOT_CPP_PATH=godot-cpp
set GAMELIFT_SDK_PATH=gamelift-server-sdk\cmake-build\Release
set OPENSSL_PATH=path\to\vcpkg\installed\x64-windows

scons platform=windows target=template_release
scons platform=windows target=template_debug

# Copy dependencies
copy gamelift-server-sdk\cmake-build\Release\aws-cpp-sdk-gamelift-server.dll bin\
copy path\to\vcpkg\installed\x64-windows\bin\libssl-3-x64.dll bin\
copy path\to\vcpkg\installed\x64-windows\bin\libcrypto-3-x64.dll bin\
```

### macOS

```bash
# Install dependencies
brew install scons cmake openssl@3

cd gamelift-gdextension

# Clone godot-cpp
git clone --recurse-submodules https://github.com/godotengine/godot-cpp.git
cd godot-cpp
git checkout godot-4.2-stable

# Build godot-cpp
scons platform=macos target=template_release
scons platform=macos target=template_debug
cd ..

# Clone GameLift SDK
git clone https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk.git gamelift-server-sdk
cd gamelift-server-sdk
mkdir cmake-build
cd cmake-build

# Build GameLift SDK
cmake -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGAMELIFT_USE_STD=1 \
  -DBUILD_FOR_UNREAL=ON \
  -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl@3 \
  -S .. -B .
make -j$(sysctl -n hw.ncpu)
cd ../..

# Build GDExtension
export GODOT_CPP_PATH=godot-cpp
export GAMELIFT_SDK_PATH=gamelift-server-sdk/cmake-build
export OPENSSL_PATH=/usr/local/opt/openssl@3

scons platform=macos target=template_release
scons platform=macos target=template_debug
```

## Troubleshooting CI Builds

### Build Fails on Windows

If the Windows build fails with vcpkg issues:
- The workflow uses vcpkg to install OpenSSL
- Check that the OpenSSL path is correct in the workflow
- MSVC paths may differ between GitHub Actions runner versions

### Build Fails on Linux

Common issues:
- Missing OpenSSL dev headers: The workflow installs `libssl-dev`
- Wrong library paths: Check that `/usr/lib/x86_64-linux-gnu/` exists

### Build Fails on macOS

Common issues:
- Homebrew OpenSSL path may vary between macOS versions
- Try `/usr/local/opt/openssl@3` or `/opt/homebrew/opt/openssl@3`

### Missing Dependencies in Artifacts

If the combined artifact is missing some libraries:
- Check the workflow logs for copy errors
- Some platforms may use different file extensions (.so vs .dylib)
- Windows DLLs might be in Debug/ or Release/ subdirectories

## Updating Godot Version

To build for a different Godot version:

1. Update the Godot version in the workflow:
   ```yaml
   git checkout godot-4.3-stable  # Change this line
   ```

2. Update the version in `gamelift.gdextension`:
   ```
   compatibility_minimum = "4.3"
   ```

3. Rebuild all platforms

## Manual Workflow Trigger

You can manually trigger the build workflow:

1. Go to **Actions** tab
2. Select **"Build GameLift GDExtension"**
3. Click **"Run workflow"**
4. Select the branch
5. Click **"Run workflow"** button

This is useful for:
- Building after making changes locally
- Creating builds for testing
- Regenerating artifacts before a release
