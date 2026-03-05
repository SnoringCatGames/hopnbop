# GameLift Anywhere Fleet Setup for Local Development
# Usage: .\gamelift-deploy\setup-anywhere.ps1
#
# Creates an Anywhere fleet, registers local machine as
# a compute, and prints Godot launch arguments.

param(
    [string]$Profile = "hopnbop",
    [string]$Region = "us-west-2",
    [string]$FleetName = "hopnbop-anywhere",
    [string]$ComputeName = "local-dev"
)

$ErrorActionPreference = "Stop"

Write-Host "=== GameLift Anywhere Setup ===" -ForegroundColor Cyan

# Step 1: Create Anywhere fleet (idempotent check).
Write-Host "[1/3] Creating Anywhere fleet..." -ForegroundColor Yellow

$existingFleets = aws gamelift list-fleets `
    --region $Region `
    --profile $Profile `
    --output json 2>$null | ConvertFrom-Json

# Check if fleet already exists by listing and filtering.
$fleetId = $null
if ($existingFleets -and $existingFleets.FleetIds) {
    foreach ($fid in $existingFleets.FleetIds) {
        $desc = aws gamelift describe-fleet-attributes `
            --fleet-ids $fid `
            --region $Region `
            --profile $Profile `
            --output json 2>$null | ConvertFrom-Json
        if ($desc.FleetAttributes[0].ComputeType -eq "ANYWHERE" -and
            $desc.FleetAttributes[0].Name -eq $FleetName) {
            $fleetId = $fid
            Write-Host "Fleet already exists: $fleetId" -ForegroundColor DarkGray
            break
        }
    }
}

if (-not $fleetId) {
    $result = aws gamelift create-fleet `
        --name $FleetName `
        --compute-type ANYWHERE `
        --anywhere-configuration "Cost=0.0" `
        --region $Region `
        --profile $Profile `
        --output json | ConvertFrom-Json

    $fleetId = $result.FleetAttributes.FleetId
    Write-Host "Created fleet: $fleetId" -ForegroundColor Green
}

# Step 2: Register local compute.
Write-Host "[2/3] Registering local compute..." -ForegroundColor Yellow

try {
    aws gamelift register-compute `
        --fleet-id $fleetId `
        --compute-name $ComputeName `
        --ip-address "127.0.0.1" `
        --region $Region `
        --profile $Profile `
        --output json | Out-Null
    Write-Host "Registered compute: $ComputeName" -ForegroundColor Green
} catch {
    Write-Host "Compute may already be registered (this is OK)" -ForegroundColor DarkGray
}

# Step 3: Get auth token.
Write-Host "[3/3] Getting auth token..." -ForegroundColor Yellow

$authResult = aws gamelift get-compute-auth-token `
    --fleet-id $fleetId `
    --compute-name $ComputeName `
    --region $Region `
    --profile $Profile `
    --output json | ConvertFrom-Json

$authToken = $authResult.AuthToken
$webSocketUrl = $authResult.GameLiftServiceSdkEndpoint

Write-Host ""
Write-Host "=== Anywhere Fleet Ready ===" -ForegroundColor Green
Write-Host ""
Write-Host "Fleet ID:      $fleetId"
Write-Host "Compute:       $ComputeName"
Write-Host "WebSocket URL: $webSocketUrl"
Write-Host "Auth Token:    $($authToken.Substring(0, 20))..."
Write-Host ""
Write-Host "Godot launch arguments:" -ForegroundColor Cyan
Write-Host "  --server --gamelift-anywhere" `
    "--gamelift-fleet-id=$fleetId" `
    "--gamelift-host-id=$ComputeName" `
    "--gamelift-auth-token=$authToken" `
    "--gamelift-websocket=$webSocketUrl"
Write-Host ""
Write-Host "Note: Auth tokens expire after 15 minutes."
Write-Host "Run this script again to get a fresh token."
