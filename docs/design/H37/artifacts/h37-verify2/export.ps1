# H37 phase 2b (h37-verify2, item 4, LG-1): wait for net.lock, take it,
# export only the pack of every preset in export_presets.cfg as a .zip,
# list each for legal/, release the lock. One blocking run.
#   pwsh -File export.ps1 [-Deadline 12:52]
param([string]$Deadline = '12:52')

$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\lsl\Repositories\hopnbop'
$h37 = "$repo\.claude\probes\H37"
$me = "$h37\h37-verify2"
$lock = "$h37\net.lock"
$godot = 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe'
$stopAt = [datetime]::ParseExact($Deadline, 'HH:mm', $null)
$exportTimeoutMs = 240000

while (Test-Path $lock) {
	if ((Get-Date) -gt $stopAt) {
		"LOCK STILL HELD at $(Get-Date -Format HH:mm:ss): $(Get-Content $lock -Raw)"
		exit 4
	}
	Start-Sleep -Seconds 15
}
"h37-verify2 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
	Out-File -FilePath $lock -Encoding ASCII
"LOCK TAKEN $(Get-Date -Format HH:mm:ss)"

try {
	$env:APPDATA = "$me\appdata"
	New-Item -ItemType Directory "$me\export" -Force | Out-Null
	Set-Location $repo
	$before = (git status --porcelain) -join "`n"
	$presets = [ordered]@{
		'Web' = 'web'
		'Windows Desktop' = 'windows'
		'Linux Server' = 'linux-server'
		'Android' = 'android'
	}
	foreach ($name in $presets.Keys) {
		$slug = $presets[$name]
		$zip = "$me\export\$slug.zip"
		Remove-Item $zip -ErrorAction SilentlyContinue
		$t0 = Get-Date
		$proc = Start-Process -FilePath $godot -NoNewWindow -PassThru `
			-ArgumentList @('--headless', '--path', '.', '--export-pack',
				"`"$name`"", "`"$zip`"") `
			-RedirectStandardOutput "$me\export-$slug.log" `
			-RedirectStandardError "$me\export-$slug.err"
		if (-not $proc.WaitForExit($exportTimeoutMs)) {
			$proc.Kill($true)
			$code = 'timeout'
		} else {
			$code = $proc.ExitCode
		}
		$secs = [int]((Get-Date) - $t0).TotalSeconds
		$size = if (Test-Path $zip) { (Get-Item $zip).Length } else { 0 }
		"EXPORT '$name': exit=$code, ${secs}s, zip bytes=$size"
	}
	$after = (git status --porcelain) -join "`n"
	if ($before -ne $after) { "GIT STATUS CHANGED:`n$after" } else { 'git status unchanged' }
	$zips = @(Get-ChildItem "$me\export\*.zip" | ForEach-Object FullName)
	if ($zips.Count -gt 0) { python -I "$me\list_pack.py" @zips }
}
finally {
	Remove-Item $lock -ErrorAction SilentlyContinue
	"LOCK RELEASED $(Get-Date -Format HH:mm:ss)"
}
