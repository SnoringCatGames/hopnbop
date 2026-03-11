# Backend Deployment Script
# Usage: .\scripts\deploy-backend.ps1
#
# Syncs GAME_VERSION in template.yaml from project.godot,
# then runs sam build and sam deploy.
#
# Prerequisites:
#   - AWS CLI configured (aws sso login --profile hopnbop)
#   - AWS SAM CLI installed
#   - Python 3.12

param(
    [string]$Profile = "hopnbop",
    [string]$Region = "us-west-2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Backend Deployment ===" -ForegroundColor Cyan

# Read version from project.godot (single source of truth).
$projectGodot = Get-Content "project.godot" -Raw
if ($projectGodot -match 'config/version="([^"]+)"') {
    $Version = $Matches[1]
} else {
    Write-Error "Could not read config/version from project.godot"
    exit 1
}

Write-Host "Version: $Version"
Write-Host ""

# Step 1: Sync GAME_VERSION in template.yaml.
Write-Host "[1/3] Syncing GAME_VERSION in template.yaml..." -ForegroundColor Yellow

$templatePath = "backend/template.yaml"
$templateContent = Get-Content $templatePath -Raw

if ($templateContent -match 'GAME_VERSION:\s*"([^"]+)"') {
    $currentVersion = $Matches[1]
    if ($currentVersion -ne $Version) {
        $templateContent = $templateContent -replace (
            'GAME_VERSION:\s*"[^"]+"'),
            "GAME_VERSION: `"$Version`""
        Set-Content -Path $templatePath -Value $templateContent -NoNewline
        Write-Host "  Updated GAME_VERSION: $currentVersion -> $Version" -ForegroundColor Green
    } else {
        Write-Host "  GAME_VERSION already $Version" -ForegroundColor DarkGray
    }
} else {
    Write-Error "Could not find GAME_VERSION in $templatePath"
    exit 1
}

# Step 2: SAM build.
Write-Host "[2/3] Running sam build..." -ForegroundColor Yellow

Push-Location backend
try {
    # --use-container builds inside a Lambda-like Docker
    # image so native extensions (bcrypt) are compiled
    # for Amazon Linux, not the local OS.
    sam build --use-container --profile $Profile --region $Region
    if ($LASTEXITCODE -ne 0) {
        Write-Error "sam build failed"
        exit 1
    }
    Write-Host "Build complete." -ForegroundColor Green

    # Step 3: SAM deploy.
    Write-Host "[3/3] Running sam deploy..." -ForegroundColor Yellow

    sam deploy --profile $Profile --region $Region
    if ($LASTEXITCODE -ne 0) {
        Write-Error "sam deploy failed"
        exit 1
    }
    Write-Host "Deploy complete." -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== Backend deployment complete ===" -ForegroundColor Green
Write-Host "Version: $Version"
