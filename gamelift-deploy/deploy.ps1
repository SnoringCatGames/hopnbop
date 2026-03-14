# GameLift Container Fleet Deployment Script
# Usage: .\gamelift-deploy\deploy.ps1 [-SkipExport]
#
# Version is read from project.godot (config/version).
#
# Prerequisites:
#   - Docker Desktop running
#   - AWS CLI configured (aws sso login --profile hopnbop)
#   - Godot CLI on PATH (for export step)
#   - Linux export templates installed in Godot

param(
    [string]$Profile = "hopnbop",
    [string]$Region = "us-west-2",
    [string]$Repository = "hopnbop-server",
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"
$AccountId = "270469481989"
$EcrUri = "$AccountId.dkr.ecr.$Region.amazonaws.com"

# Read version from project.godot (single source of truth).
$projectGodot = Get-Content "project.godot" -Raw
if ($projectGodot -match 'config/version="([^"]+)"') {
    $Version = $Matches[1]
} else {
    Write-Error "Could not read config/version from project.godot"
    exit 1
}

# Read protocol version from project.godot.
if ($projectGodot -match 'config/protocol_version=(\d+)') {
    $ProtocolVersion = $Matches[1]
} else {
    Write-Error "Could not read config/protocol_version from project.godot"
    exit 1
}

# Warn if backend/template.yaml versions are out of sync.
$templateYaml = Get-Content "backend/template.yaml" -Raw
if ($templateYaml -match 'GAME_VERSION:\s*"([^"]+)"') {
    $backendVersion = $Matches[1]
    if ($backendVersion -ne $Version) {
        Write-Warning "backend/template.yaml GAME_VERSION is `"$backendVersion`" but project.godot is `"$Version`". Remember to update and redeploy the backend."
    }
} else {
    Write-Warning "Could not read GAME_VERSION from backend/template.yaml"
}
if ($templateYaml -match 'PROTOCOL_VERSION:\s*"(\d+)"') {
    $backendProtocol = $Matches[1]
    if ($backendProtocol -ne $ProtocolVersion) {
        Write-Warning "backend/template.yaml PROTOCOL_VERSION is `"$backendProtocol`" but project.godot is `"$ProtocolVersion`". Remember to update and redeploy the backend."
    }
} else {
    Write-Warning "Could not read PROTOCOL_VERSION from backend/template.yaml"
}
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

    # Delete stale .pck to force a fresh export.
    # Godot's --export-pack sometimes skips writing
    # if the output file already exists.
    $pckPath = "build/linux/hopnbop_server.pck"
    if (Test-Path $pckPath) {
        Remove-Item $pckPath
        Write-Host "  Removed stale .pck" -ForegroundColor DarkGray
    }

    # Reimport to regenerate the script class cache.
    # Headless export does not reimport automatically.
    & godot --headless --import
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Reimport returned non-zero (may be OK)"
    }

    # Export the .pck only. The Linux server binary
    # is platform-specific and unchanged between code
    # deploys. --export-release fails on Windows due
    # to Linux .so dependency copy issues.
    & godot --headless --export-pack "Linux Server" $pckPath
    # Godot may return non-zero due to GDExtension DLL
    # lock warnings on Windows. Verify the .pck exists.
    if (-not (Test-Path $pckPath)) {
        Write-Error "Godot export failed (no .pck produced)"
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

# Fetch server API key from Secrets Manager.
$ServerApiKey = aws secretsmanager get-secret-value `
    --secret-id "hopnbop/server-api-key" `
    --region $Region `
    --profile $Profile `
    --query "SecretString" --output text 2>$null

if (-not $ServerApiKey) {
    Write-Warning "Could not fetch hopnbop/server-api-key from Secrets Manager. Env var will not be set."
    $ServerApiKey = "REPLACE_WITH_SECRET"
}

# Read the definition template, update image URI and inject the API key.
$definition = Get-Content "gamelift-deploy/container-group-definition.json" | ConvertFrom-Json
$definition.GameServerContainerDefinition.ImageUri = $ImageTag
foreach ($envVar in $definition.GameServerContainerDefinition.EnvironmentOverride) {
    if ($envVar.Name -eq "SERVER_API_KEY") {
        $envVar.Value = $ServerApiKey
    }
}

# Write the game-server-container-definition to a
# temp file. Passing JSON inline from PowerShell
# mangles special characters.
$gameServerDef = $definition.GameServerContainerDefinition | ConvertTo-Json -Depth 10 -Compress
$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Value $gameServerDef -NoNewline

aws gamelift update-container-group-definition `
    --name $definition.Name `
    --game-server-container-definition "file://$tempFile" `
    --total-memory-limit-mebibytes $definition.TotalMemoryLimitMebibytes `
    --total-vcpu-limit $definition.TotalVcpuLimit `
    --version-description "Deploy v$Version" `
    --region $Region `
    --profile $Profile

Remove-Item $tempFile -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Write-Error "Container group definition update failed"
    exit 1
}

Write-Host "Container group definition updated." -ForegroundColor Green

# Step 6: Update fleet to use new container group.
$FleetId = "containerfleet-9836594e-0c96-4887-a8d5-be7f3541db36"
Write-Host "[6/6] Updating fleet $FleetId..." -ForegroundColor Yellow

aws gamelift update-container-fleet `
    --fleet-id $FleetId `
    --game-server-container-group-definition-name $definition.Name `
    --region $Region `
    --profile $Profile

if ($LASTEXITCODE -ne 0) {
    Write-Error "Fleet update failed"
    exit 1
}

Write-Host ""
Write-Host "=== Deployment complete ===" -ForegroundColor Green
Write-Host "Image pushed: $ImageTag"
Write-Host "Fleet deployment triggered."
Write-Host ""
Write-Host "Monitor with:"
Write-Host "  aws gamelift list-fleet-deployments --fleet-id $FleetId --region $Region --profile $Profile"
