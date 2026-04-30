# Cloudflare Pages + R2 split deploy.
#
# Pages has a 25 MiB per-file cap which our index.wasm (~38 MB)
# blows through. Strategy: park the engine assets fetched via
# Godot's `executable` config (.wasm, .audio.worklet.js,
# .audio.position.worklet.js) and the .pck on R2; everything
# else goes to Pages.
#
# Repeatable: reads credentials.env, builds web/, uploads
# heavies to R2, patches GODOT_CONFIG to absolute R2 URLs,
# drops the heavies from a staging copy, deploys staging to
# Pages.
#
# Prereqs:
#   - Token in CLOUDFLARE_PAGES_TOKEN with Pages:Edit AND
#     Workers R2 Storage:Edit AND Account Settings:Read.
#   - CLOUDFLARE_ACCOUNT_ID env (hex, not slug).
#   - Bucket hopnbop-assets created (this script idempotently
#     creates it on first run).
#   - npm/npx available.

[CmdletBinding()]
param(
	[switch]$SkipExport,
	[string]$Bucket = "hopnbop-assets",
	[string]$Project = "hopnbop-website",
	[string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$web = "$repoRoot\web"
$staging = "$env:TEMP\hopnbop-pages-staging"

# Files Godot's loader pulls via `executable` prefix + the .pck.
# Anything in this list goes to R2 instead of Pages.
$heavyAssets = @(
	"index.wasm",
	"index.pck",
	"index.audio.worklet.js",
	"index.audio.position.worklet.js"
)

# --------------------------------------------------------------
# Source credentials
# --------------------------------------------------------------
Get-Content "$HOME\.hopnbop-migration\credentials.env" | ForEach-Object {
	if ($_ -match '^([A-Z_]+)=(.*)$') {
		Set-Item "Env:$($Matches[1])" $Matches[2]
	}
}
if (-not $env:CLOUDFLARE_PAGES_TOKEN) {
	throw "CLOUDFLARE_PAGES_TOKEN missing in credentials.env"
}
$env:CLOUDFLARE_API_TOKEN = $env:CLOUDFLARE_PAGES_TOKEN
$env:CLOUDFLARE_ACCOUNT_ID = "c97b21157100dde27a8715fdfba1d22a"

function Run {
	param([string]$desc, [scriptblock]$cmd)
	Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $desc" -ForegroundColor Cyan
	& $cmd
	if ($LASTEXITCODE -ne 0) { throw "$desc failed (exit $LASTEXITCODE)" }
}

function Get-MimeType {
	param([string]$filename)
	switch -Regex ($filename) {
		'\.wasm$' { return 'application/wasm' }
		'\.pck$'  { return 'application/octet-stream' }
		'\.js$'   { return 'application/javascript' }
		'\.png$'  { return 'image/png' }
		default   { return 'application/octet-stream' }
	}
}

# --------------------------------------------------------------
# 1. Optional: re-export the Godot web build.
# --------------------------------------------------------------
if (-not $SkipExport) {
	Run "Godot web export" {
		Push-Location $repoRoot
		try {
			New-Item -ItemType Directory -Force -Path "build\web" | Out-Null
			godot --headless --export-release "Web" `
				"build\web\index.html"
			# Godot returns nonzero on cosmetic warnings; verify
			# the artifact landed.
			if (-not (Test-Path "build\web\index.wasm")) {
				throw "Godot export didn't produce build\web\index.wasm"
			}
			Copy-Item "build\web\*" $web -Force -Recurse
		} finally { Pop-Location }
	}
}

# --------------------------------------------------------------
# 2a. Pre-flight R2 hard cap. If the bucket is already at or
# above $R2_HARD_GB (default 9.5 GB), refuse to upload more.
# Free tier is 10 GB; this guards against silently slipping
# into Cloudflare's paid tier.
# --------------------------------------------------------------
$r2HardGb = 9.5
$listHeaders = @{ Authorization = "Bearer $env:CLOUDFLARE_API_TOKEN" }
# /usage aggregates with lag; list-objects is real-time. Sum
# object sizes. For >1000 objects we'd page; we don't.
$listUrl = "https://api.cloudflare.com/client/v4/accounts/$env:CLOUDFLARE_ACCOUNT_ID/r2/buckets/$Bucket/objects?per_page=1000"
try {
	$listResp = Invoke-RestMethod -Uri $listUrl -Headers $listHeaders
	$totalBytes = ($listResp.result | Measure-Object -Property size -Sum).Sum
	if (-not $totalBytes) { $totalBytes = 0 }
	$usedGb = [math]::Round($totalBytes / 1GB, 2)
	Write-Host "[$(Get-Date -Format 'HH:mm:ss')] R2 usage: $usedGb GB / $r2HardGb GB hard / 10 GB free tier" -ForegroundColor Cyan
	if ($usedGb -ge $r2HardGb) {
		throw "R2 bucket $Bucket is at $usedGb GB (>= $r2HardGb GB hard cap). Refusing to upload. Free space first or raise the cap."
	}
} catch [Microsoft.PowerShell.Commands.HttpResponseException] {
	# Bucket may not exist yet on first run — that's fine, the
	# next step creates it. Any other HTTP error: surface and
	# bail.
	if ($_.Exception.Response.StatusCode -ne 404) {
		throw
	}
}

# --------------------------------------------------------------
# 2b. Ensure R2 bucket exists.
# --------------------------------------------------------------
Run "ensure R2 bucket $Bucket" {
	$existing = npx -y wrangler@latest r2 bucket list 2>&1 |
		Select-String -Pattern "name:\s+$Bucket" -Quiet
	if (-not $existing) {
		npx -y wrangler@latest r2 bucket create $Bucket | Out-Null
		# Public access via r2.dev URL.
		npx -y wrangler@latest r2 bucket dev-url enable $Bucket | Out-Null
	}
}

# --------------------------------------------------------------
# 3. Bucket CORS — r2.dev URLs ship permissive defaults
#    (Access-Control-Allow-Origin: *) so the Godot loader's
#    fetch() against them works without explicit config. We
#    drop the page's COEP header below, so CORP isn't required
#    either. If a future setup hits CORS issues we can configure
#    bucket-level rules via the dashboard.
# --------------------------------------------------------------

# --------------------------------------------------------------
# 4. Upload heavy assets to R2.
# --------------------------------------------------------------
foreach ($f in $heavyAssets) {
	$path = Join-Path $web $f
	if (-not (Test-Path $path)) {
		Write-Host "  skip (missing): $f" -ForegroundColor Yellow
		continue
	}
	Run "upload $f to r2://$Bucket" {
		# --remote: wrangler 4.x defaults `r2 object put` to a
		# local dev simulator; without --remote, the upload
		# silently lands in ~/.wrangler/ instead of R2.
		npx -y wrangler@latest r2 object put `
			"${Bucket}/${f}" --file "$path" `
			--content-type (Get-MimeType $f) `
			--remote | Out-Null
	}
}

# --------------------------------------------------------------
# 5. Discover the bucket's public r2.dev URL.
# --------------------------------------------------------------
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] fetch R2 public URL" -ForegroundColor Cyan
$urlOut = npx -y wrangler@latest r2 bucket dev-url get $Bucket 2>&1 | Out-String
if ($urlOut -notmatch '(https?://[a-z0-9\-]+\.r2\.dev)') {
	throw "Could not parse r2.dev URL from: $urlOut"
}
$r2BaseUrl = $Matches[1]
Write-Host "R2 base URL: $r2BaseUrl" -ForegroundColor Green

# --------------------------------------------------------------
# 6. Build a staging copy of web/ — same files, minus the
#    heavies, with GODOT_CONFIG patched to absolute R2 URLs.
# --------------------------------------------------------------
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
Copy-Item -Recurse $web $staging
foreach ($f in $heavyAssets) {
	$p = Join-Path $staging $f
	if (Test-Path $p) { Remove-Item $p -Force }
}

# Patch GODOT_CONFIG in index.html. The original has
# "executable":"index" and "mainPack":"index.pck?...". We
# replace with absolute R2 URLs; Godot's Engine class accepts
# absolute URLs for both fields.
$indexPath = "$staging\index.html"
$content = Get-Content $indexPath -Raw
$content = $content -replace `
	'"executable":"index"', `
	('"executable":"' + $r2BaseUrl + '/index"')
$content = $content -replace `
	'"mainPack":"index\.pck([^"]*)"', `
	('"mainPack":"' + $r2BaseUrl + '/index.pck$1"')
[IO.File]::WriteAllText($indexPath, $content, [Text.UTF8Encoding]::new($false))

# Drop _headers — it's only relevant if the wasm is same-origin.
# With wasm cross-origin from R2, the page no longer needs to be
# crossOriginIsolated. Removing the COOP/COEP headers also avoids
# blocking the cross-origin wasm fetch in some browsers.
$headersPath = "$staging\_headers"
if (Test-Path $headersPath) { Remove-Item $headersPath -Force }

Write-Host "Staging at $staging ready" -ForegroundColor Green

# --------------------------------------------------------------
# 7. Deploy staging to Cloudflare Pages.
# --------------------------------------------------------------
Run "wrangler pages deploy" {
	npx -y wrangler@latest pages deploy $staging `
		--project-name=$Project --branch=$Branch `
		--commit-dirty=true | Out-Null
}

Write-Host ""
Write-Host "Deploy done. Verify:" -ForegroundColor Green
Write-Host "  https://$Project.pages.dev"
Write-Host ""
Write-Host "Browser console quick check:"
Write-Host '  fetch("https://' + $r2BaseUrl.Replace("https://","") + '/index.wasm", {method:"HEAD"}).then(r => r.headers.get("cross-origin-resource-policy"))'
