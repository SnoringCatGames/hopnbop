# GameLift Container Fleet Deployment Script
# Usage: .\gamelift-deploy\deploy.ps1 [-Version "0.1.0"] [-SkipExport]
#
# Prerequisites:
#   - Docker Desktop running
#   - AWS CLI configured (aws sso login --profile hopnbop)
#   - Godot CLI on PATH (for export step)
#   - Linux export templates installed in Godot

param(
    [string]$Version = "0.1.0",
    [string]$Profile = "hopnbop",
    [string]$Region = "us-west-2",
    [string]$Repository = "hopnbop-server",
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"
$AccountId = "270469481989"
$EcrUri = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$ImageTag = "$EcrUri/${Repository}:${Version}"

Write-Host "=== GameLift Server Deployment ===" -ForegroundColor Cyan
Write-Host "Version: $Version"
Write-Host "Image:   $ImageTag"
Write-Host ""

# Step 1: Export Godot Linux server.
if (-not $SkipExport) {
    Write-Host "[1/5] Exporting Godot Linux server..." -ForegroundColor Yellow

    # Ensure build directory exists.
    New-Item -ItemType Directory -Force -Path "build/linux" | Out-Null

    # Export using Godot CLI. Requires godot to be on PATH.
    & godot --headless --export-release "Linux Server" "build/linux/hopnbop_server.x86_64"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Godot export failed"
        exit 1
    }
    Write-Host "Export complete." -ForegroundColor Green
} else {
    Write-Host "[1/5] Skipping export (--SkipExport)" -ForegroundColor DarkGray
}

# Step 2: Build Docker image.
Write-Host "[2/5] Building Docker image..." -ForegroundColor Yellow
docker build -t "${Repository}:${Version}" .
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed"
    exit 1
}
Write-Host "Docker build complete." -ForegroundColor Green

# Step 3: Login to ECR.
Write-Host "[3/5] Logging in to ECR..." -ForegroundColor Yellow
$password = aws ecr get-login-password --region $Region --profile $Profile
$password | docker login --username AWS --password-stdin $EcrUri
if ($LASTEXITCODE -ne 0) {
    Write-Error "ECR login failed"
    exit 1
}

# Step 4: Tag and push.
Write-Host "[4/5] Pushing to ECR..." -ForegroundColor Yellow
docker tag "${Repository}:${Version}" $ImageTag
docker push $ImageTag
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker push failed"
    exit 1
}

# Also tag as latest.
$LatestTag = "$EcrUri/${Repository}:latest"
docker tag "${Repository}:${Version}" $LatestTag
docker push $LatestTag
Write-Host "Push complete." -ForegroundColor Green

# Step 5: Update container group definition.
Write-Host "[5/5] Updating container group definition..." -ForegroundColor Yellow

# Read the definition template and update the image URI.
$definition = Get-Content "gamelift-deploy/container-group-definition.json" | ConvertFrom-Json
$definition.GameServerContainerDefinition.ImageUri = $ImageTag
$tempFile = [System.IO.Path]::GetTempFileName()
$definition | ConvertTo-Json -Depth 10 | Set-Content $tempFile

aws gamelift create-container-group-definition `
    --cli-input-json "file://$tempFile" `
    --region $Region `
    --profile $Profile 2>&1

Remove-Item $tempFile

Write-Host ""
Write-Host "=== Deployment complete ===" -ForegroundColor Green
Write-Host "Image pushed: $ImageTag"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. If this is the first deploy, create the fleet:"
Write-Host "     .\gamelift-deploy\create-fleet.sh"
Write-Host "  2. If fleet already exists, update it to use"
Write-Host "     the new container group definition version."
