# Build script for GameLift GDExtension on Windows
# This script automates the build process for Windows platforms

param(
	[switch]$Debug,
	[switch]$Release,
	[switch]$Both,
	[switch]$SkipVcpkg,
	[string]$VcpkgPath = ""
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Warning { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host $msg -ForegroundColor Red }

Write-Info "=== GameLift GDExtension Windows Build ==="
Write-Info ""

# Determine build targets
if (-not $Debug -and -not $Release -and -not $Both) {
	Write-Info "No build target specified, building both debug and release"
	$Both = $true
}

if ($Both) {
	$Debug = $true
	$Release = $true
}

# Get the script directory
$SCRIPT_DIR = $PSScriptRoot
Set-Location $SCRIPT_DIR

# Step 1: Check for required tools
Write-Info "[1/6] Checking for required tools..."

# Check Python
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
	Write-Error "Python not found. Please install Python 3.x"
	exit 1
}
Write-Success "✓ Python found: $(python --version)"

# Check SCons
if (-not (Get-Command scons -ErrorAction SilentlyContinue)) {
	Write-Warning "SCons not found. Installing..."
	python -m pip install scons
}
Write-Success "✓ SCons found"

# Check Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	Write-Error "Git not found. Please install Git"
	exit 1
}
Write-Success "✓ Git found"

# Check CMake
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
	Write-Error "CMake not found. Please install CMake"
	exit 1
}
Write-Success "✓ CMake found: $(cmake --version | Select-Object -First 1)"

# Use CMake 3.27 for GameLift SDK if available (needed for compatibility)
$CMAKE_327_PATH = "C:\cmake-3.27.9-windows-x86_64\bin\cmake.exe"
if (Test-Path $CMAKE_327_PATH) {
	Write-Info "Using CMake 3.27 for GameLift SDK build"
	$CMAKE_FOR_GAMELIFT = $CMAKE_327_PATH
}
else {
	Write-Warning "CMake 3.27 not found, using system CMake (may have compatibility issues)"
	$CMAKE_FOR_GAMELIFT = "cmake"
}

# Check for Visual Studio / MSVC
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
	$vsPath = & $vsWhere -latest -property installationPath
	if ($vsPath) {
		Write-Success "✓ Visual Studio found at: $vsPath"
	}
}
else {
	Write-Warning "Visual Studio detection tool not found. Make sure MSVC is installed."
}

# Step 2: Setup vcpkg and OpenSSL
Write-Info ""
Write-Info "[2/6] Setting up vcpkg and OpenSSL..."

$VCPKG_DIR = ""
if ($VcpkgPath -and (Test-Path $VcpkgPath)) {
	$VCPKG_DIR = $VcpkgPath
	Write-Info "Using provided vcpkg path: $VCPKG_DIR"
}
elseif ($env:VCPKG_ROOT -and (Test-Path $env:VCPKG_ROOT)) {
	$VCPKG_DIR = $env:VCPKG_ROOT
	Write-Info "Using VCPKG_ROOT: $VCPKG_DIR"
}
elseif (Test-Path "$SCRIPT_DIR\..\vcpkg") {
	$VCPKG_DIR = "$SCRIPT_DIR\..\vcpkg"
	Write-Info "Found vcpkg in parent directory"
}
elseif (Test-Path "$SCRIPT_DIR\vcpkg") {
	$VCPKG_DIR = "$SCRIPT_DIR\vcpkg"
	Write-Info "Found vcpkg in current directory"
}
else {
	if (-not $SkipVcpkg) {
		Write-Info "vcpkg not found. Cloning..."
		git clone https://github.com/microsoft/vcpkg.git "$SCRIPT_DIR\vcpkg"
		$VCPKG_DIR = "$SCRIPT_DIR\vcpkg"

		Write-Info "Bootstrapping vcpkg..."
		& "$VCPKG_DIR\bootstrap-vcpkg.bat"
	}
 else {
		Write-Warning "Skipping vcpkg setup as requested. Make sure OpenSSL is available!"
	}
}

$OPENSSL_PATH = ""
if ($VCPKG_DIR) {
	# Install OpenSSL via vcpkg if not already installed
	$vcpkgExe = "$VCPKG_DIR\vcpkg.exe"
	if (Test-Path $vcpkgExe) {
		Write-Info "Installing OpenSSL via vcpkg..."
		& $vcpkgExe install openssl:x64-windows
		$OPENSSL_PATH = "$VCPKG_DIR\installed\x64-windows"
		Write-Success "✓ OpenSSL installed at: $OPENSSL_PATH"
	}
}

# Step 3: Build godot-cpp
Write-Info ""
Write-Info "[3/6] Building godot-cpp..."

if (-not (Test-Path "godot-cpp")) {
	Write-Info "Cloning godot-cpp..."
	git clone --recurse-submodules https://github.com/godotengine/godot-cpp.git
	Set-Location godot-cpp
	git checkout godot-4.5-stable
	Set-Location ..
}

Set-Location godot-cpp

if ($Release) {
	Write-Info "Building godot-cpp (Release)..."
	scons platform=windows target=template_release
}

if ($Debug) {
	Write-Info "Building godot-cpp (Debug)..."
	scons platform=windows target=template_debug
}

Set-Location ..
Write-Success "✓ godot-cpp built"

# Step 4: Build GameLift Server SDK
Write-Info ""
Write-Info "[4/6] Building GameLift Server SDK..."

if (-not (Test-Path "gamelift-server-sdk")) {
	Write-Info "Cloning GameLift Server SDK..."
	git clone https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk.git gamelift-server-sdk
}

if (-not (Test-Path "gamelift-server-sdk\cmake-build")) {
	New-Item -ItemType Directory -Path "gamelift-server-sdk\cmake-build" -Force | Out-Null
}

Set-Location gamelift-server-sdk

# Patch CMakeLists.txt files to enforce /MT runtime library (for CI/CD compatibility)
Write-Info "Patching GameLift SDK CMakeLists.txt for /MT runtime..."
$rootCMake = Get-Content "CMakeLists.txt" -Raw
if ($rootCMake -notmatch "CMAKE_MSVC_RUNTIME_LIBRARY") {
	Write-Info "  Patching root CMakeLists.txt..."
	$rootCMake = $rootCMake -replace '(set\(GameLiftServerSdk_DEFAULT_ARGS)', @'
# Force /MT runtime library for Windows MSVC to match Godot GDExtension
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  # Also set it in DEFAULT_ARGS for sub-projects
  list(APPEND GameLiftServerSdk_DEFAULT_ARGS
    "-DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

$1'@
	Set-Content "CMakeLists.txt" -Value $rootCMake -NoNewline
}

$sdkCMake = Get-Content "gamelift-server-sdk\CMakeLists.txt" -Raw
if ($sdkCMake -notmatch "CMAKE_MSVC_RUNTIME_LIBRARY") {
	Write-Info "  Patching gamelift-server-sdk/CMakeLists.txt..."
	$sdkCMake = $sdkCMake -replace '(if\(MSVC\)\s+# Unlock object file size limit\s+add_compile_options\(/bigobj\))',@'
if(MSVC)
    # Unlock object file size limit
    add_compile_options(/bigobj)
    # Use static runtime library (/MT) to match Godot GDExtension
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    # Also force via compiler flags as fallback
    string(REPLACE "/MD" "/MT" CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE}")
    string(REPLACE "/MD" "/MT" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
    string(REPLACE "/MDd" "/MTd" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")'@
	Set-Content "gamelift-server-sdk\CMakeLists.txt" -Value $sdkCMake -NoNewline
}

Set-Location cmake-build

Write-Info "Configuring GameLift SDK with CMake 3.27..."
# Set OPENSSL_ROOT_DIR environment variable so nested CMake projects can find it
if ($OPENSSL_PATH) {
	$env:OPENSSL_ROOT_DIR = $OPENSSL_PATH.Replace('\', '/')
	Write-Host "  Set OPENSSL_ROOT_DIR=$env:OPENSSL_ROOT_DIR"
}

$cmakeArgs = @(
	"-G", "Visual Studio 17 2022",
	"-A", "x64",
	"-DCMAKE_BUILD_TYPE=Release",
	"-DGAMELIFT_USE_STD=1",
	"-DBUILD_SHARED_LIBS=OFF",  # Build as static library for GDExtension
	"-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",  # Use static runtime (/MT) to match GDExtension
	"-DCMAKE_CXX_FLAGS_RELEASE=/MT /O2 /Ob2 /DNDEBUG",  # Force /MT explicitly
	"-DCMAKE_C_FLAGS_RELEASE=/MT /O2 /Ob2 /DNDEBUG",    # Force /MT explicitly
	"-DRUN_UNIT_TESTS=OFF",  # Skip unit tests (they have runtime library issues)
	"-S", "..", "-B", "."
)

& $CMAKE_FOR_GAMELIFT @cmakeArgs

if ($LASTEXITCODE -ne 0) {
	Write-Error "CMake configuration failed"
	exit 1
}

Write-Info "Building GameLift SDK..."
& $CMAKE_FOR_GAMELIFT --build . --config Release

if ($LASTEXITCODE -ne 0) {
	Write-Error "GameLift SDK build failed"
	exit 1
}

Set-Location ..\..
Write-Success "✓ GameLift Server SDK built"

# Step 5: Build GDExtension
Write-Info ""
Write-Info "[5/6] Building GameLift GDExtension..."

$env:GODOT_CPP_PATH = "godot-cpp"
$env:GAMELIFT_SDK_PATH = "gamelift-server-sdk\cmake-build\prefix"
if ($OPENSSL_PATH) {
	$env:OPENSSL_PATH = $OPENSSL_PATH
}
Write-Host "  GODOT_CPP_PATH=$env:GODOT_CPP_PATH"
Write-Host "  GAMELIFT_SDK_PATH=$env:GAMELIFT_SDK_PATH"
Write-Host "  OPENSSL_PATH=$env:OPENSSL_PATH"

if ($Release) {
	Write-Info "Building GDExtension (Release)..."
	scons platform=windows target=template_release
}

if ($Debug) {
	Write-Info "Building GDExtension (Debug)..."
	scons platform=windows target=template_debug
}

Write-Success "✓ GDExtension built"

# Step 6: Copy dependencies
Write-Info ""
Write-Info "[6/6] Copying dependencies..."

if (-not (Test-Path "bin")) {
	New-Item -ItemType Directory -Path "bin" -Force | Out-Null
}

# Copy GameLift SDK DLL
$gameliftDll = "gamelift-server-sdk\cmake-build\prefix\bin\aws-cpp-sdk-gamelift-server.dll"
if (Test-Path $gameliftDll) {
	Copy-Item $gameliftDll "bin\" -Force
	Write-Success "✓ Copied aws-cpp-sdk-gamelift-server.dll"
}
else {
	Write-Warning "GameLift SDK DLL not found at: $gameliftDll"
}

# Copy OpenSSL DLLs
if ($OPENSSL_PATH) {
	$opensslBin = "$OPENSSL_PATH\bin"
	if (Test-Path "$opensslBin\libssl-3-x64.dll") {
		Copy-Item "$opensslBin\libssl-3-x64.dll" "bin\" -Force
		Write-Success "✓ Copied libssl-3-x64.dll"
	}
	if (Test-Path "$opensslBin\libcrypto-3-x64.dll") {
		Copy-Item "$opensslBin\libcrypto-3-x64.dll" "bin\" -Force
		Write-Success "✓ Copied libcrypto-3-x64.dll"
	}
}

# Copy to addons folder
Write-Info ""
Write-Info "Installing to addons/gamelift/..."
$addonsPath = "..\addons\gamelift"
if (-not (Test-Path $addonsPath)) {
	New-Item -ItemType Directory -Path $addonsPath -Force | Out-Null
}

if (-not (Test-Path "$addonsPath\bin")) {
	New-Item -ItemType Directory -Path "$addonsPath\bin" -Force | Out-Null
}

# Copy .gdextension file
Copy-Item "gamelift.gdextension" $addonsPath -Force

# Copy binaries
Copy-Item "bin\*.dll" "$addonsPath\bin\" -Force
if (Test-Path "bin\*.lib") {
	Copy-Item "bin\*.lib" "$addonsPath\bin\" -Force
}

Write-Success ""
Write-Success "=== Build Complete! ==="
Write-Info ""
Write-Info "Built files:"
Get-ChildItem -Path "bin" -Filter "*.dll" | ForEach-Object { Write-Info "  - bin\$($_.Name)" }
Write-Info ""
Write-Info "Installed to: $addonsPath"
Write-Info ""
