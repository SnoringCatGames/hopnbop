# Fetch Edgegap container stdout/stderr for a deploy.
#
# Edgegap exposes container logs at
#   GET /v1/deployment/<request_id>/container-logs
# (note: singular "deployment", not the "deployments" used by
# the list endpoint — different API surface).
#
# Usage:
#   .\scripts\edgegap-logs.ps1 -RequestId 3830dd391c64
#   .\scripts\edgegap-logs.ps1 -Latest         # most recent deploy
#   .\scripts\edgegap-logs.ps1 -Tail 50 -RequestId ...
#
# Reads EDGEGAP_TOKEN from ~/.hopnbop-migration/credentials.env.
[CmdletBinding()]
param(
    [string]$RequestId,
    [switch]$Latest,
    [int]$Tail = 0,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$credsFile = Join-Path $HOME ".hopnbop-migration\credentials.env"
if (-not (Test-Path $credsFile)) {
    throw "Missing $credsFile"
}
$token = (Get-Content $credsFile | Where-Object {
    $_ -like "EDGEGAP_TOKEN=*"
}).Split('=', 2)[1]
if (-not $token) {
    throw "EDGEGAP_TOKEN not in $credsFile"
}

if ($Latest) {
    $list = Invoke-RestMethod -Uri "https://api.edgegap.com/v1/deployments?limit=1" `
        -Headers @{ Authorization = "token $token" }
    if (-not $list.data -or $list.data.Count -eq 0) {
        throw "No deployments returned"
    }
    $RequestId = $list.data[0].request_id
    Write-Host "Latest deploy: $RequestId" -ForegroundColor Cyan
}

if (-not $RequestId) {
    throw "Specify -RequestId <id> or -Latest"
}

$resp = Invoke-RestMethod -Uri "https://api.edgegap.com/v1/deployment/$RequestId/container-logs" `
    -Headers @{ Authorization = "token $token" }

if ($Json) {
    $resp | ConvertTo-Json -Depth 10
    return
}

$logs = $resp.logs
if ($Tail -gt 0 -and $logs) {
    $lines = $logs -split "`n"
    if ($lines.Count -gt $Tail) {
        $logs = ($lines | Select-Object -Last $Tail) -join "`n"
    }
}

if ($resp.has_crashed) {
    Write-Host "=== CRASH DETECTED ===" -ForegroundColor Red
    if ($resp.crash_data) {
        Write-Host $resp.crash_data
    }
    if ($resp.crash_logs) {
        Write-Host "--- crash_logs ---"
        Write-Host $resp.crash_logs
    }
    Write-Host "=== container stdout/stderr ===" -ForegroundColor Yellow
}

Write-Host $logs
