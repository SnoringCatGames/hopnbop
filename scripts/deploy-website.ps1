# Website Deployment Script
# Usage: .\scripts\deploy-website.ps1 [-SkipExport]
#
# Syncs the web/ directory to S3 and invalidates the
# CloudFront cache. Optionally exports the Godot web
# build first.
#
# Prerequisites:
#   - AWS CLI configured (aws sso login --profile hopnbop)
#   - Godot CLI on PATH (for export step)
#   - Web export templates installed in Godot

param(
    [string]$Profile = "hopnbop",
    [string]$Region = "us-west-2",
    [string]$Bucket = "hopnbop-website",
    [string]$DistributionId = "E3LT833LSVTW9R",
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"

Write-Host "=== Website Deployment ===" -ForegroundColor Cyan
Write-Host "Bucket: s3://$Bucket"
Write-Host ""

# Step 1: Export Godot web build.
if (-not $SkipExport) {
    Write-Host "[1/4] Exporting Godot web build..." -ForegroundColor Yellow

    New-Item -ItemType Directory -Force -Path "build/web" | Out-Null

    & godot --headless --import
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Reimport returned non-zero (may be OK)"
    }

    # Hide the GameLift GDExtension before web export.
    # The extension has no web/wasm32 binary. When the
    # Emscripten runtime (which has no GDExtension
    # support) tries to load it, the failure cascades
    # through the GDScript type system and breaks
    # scripts that access G.settings. Temporarily
    # renaming the .gdextension file prevents Godot
    # from discovering it during export.
    $gdextPath = "addons/gamelift/gamelift.gdextension"
    $gdextBackup = "$gdextPath.disabled"
    $didHideExt = $false
    if (Test-Path $gdextPath) {
        Move-Item $gdextPath $gdextBackup
        $didHideExt = $true
    }

    try {
        & godot --headless --export-release "Web" "build/web/index.html"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Godot web export failed"
            exit 1
        }
    } finally {
        if ($didHideExt -and (Test-Path $gdextBackup)) {
            Move-Item $gdextBackup $gdextPath
        }
    }
    Write-Host "Export complete." -ForegroundColor Green
} else {
    Write-Host "[1/4] Skipping export (--SkipExport)" -ForegroundColor DarkGray
}

# Step 2: Copy web export files into web/ directory.
if (-not $SkipExport) {
    Write-Host "[2/4] Copying export files to web/..." -ForegroundColor Yellow

    # Copy all build output files including the processed
    # index.html. The shell template lives at web/shell.html
    # and is consumed by the export. The exported index.html
    # has all $GODOT_* placeholders replaced.
    Get-ChildItem "build/web" -File | ForEach-Object {
        Copy-Item $_.FullName "web/$($_.Name)" -Force
        Write-Host "  Copied $($_.Name)" -ForegroundColor DarkGray
    }
    Write-Host "Copy complete." -ForegroundColor Green
} else {
    Write-Host "[2/4] Skipping copy (--SkipExport)" -ForegroundColor DarkGray
}

# Step 3: Sync web/ to S3.
Write-Host "[3/4] Syncing to S3..." -ForegroundColor Yellow

# Sync all files, excluding dev-only files.
aws s3 sync web/ "s3://$Bucket/" `
    --delete `
    --exclude ".gitkeep" `
    --exclude "*.md" `
    --cache-control "max-age=3600" `
    --profile $Profile `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Error "S3 sync failed"
    exit 1
}

# Set longer cache for immutable assets (wasm, pck).
$immutableTypes = @("*.wasm", "*.pck")
foreach ($pattern in $immutableTypes) {
    aws s3 cp "s3://$Bucket/" "s3://$Bucket/" `
        --recursive `
        --exclude "*" `
        --include $pattern `
        --cache-control "max-age=86400" `
        --metadata-directive REPLACE `
        --profile $Profile `
        --region $Region
}

Write-Host "S3 sync complete." -ForegroundColor Green

# Step 4: Invalidate CloudFront cache.
Write-Host "[4/4] Invalidating CloudFront cache..." -ForegroundColor Yellow

aws cloudfront create-invalidation `
    --distribution-id $DistributionId `
    --paths "/*" `
    --profile $Profile `
    --region $Region | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "CloudFront invalidation failed"
    exit 1
}

Write-Host "CloudFront invalidation created." -ForegroundColor Green

Write-Host ""
Write-Host "=== Deployment complete ===" -ForegroundColor Green
Write-Host "Site: https://hopnbop.net"
