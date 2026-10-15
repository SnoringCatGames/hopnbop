$root = 'C:\Users\lsl\Repositories\hopnbop'
$base = Join-Path $root '.claude\probes\H37\h37-stats-ops'
$out = Join-Path $base 'gut'
New-Item -ItemType Directory -Force $out | Out-Null
$env:APPDATA = Join-Path $base 'appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$tests = $args
foreach ($t in $tests) {
  $name = [IO.Path]::GetFileNameWithoutExtension($t)
  $log = Join-Path $out "$name.log"
  & 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless -s --path $root addons/gut/gut_cmdln.gd "-gtest=res://$t" -gexit *> $log
  $code = $LASTEXITCODE
  $summary = Select-String -Path $log -Pattern 'Passing Tests|Failing Tests|Pending|Asserts|Nothing was run|^Tests\s|All tests passed|SCRIPT ERROR|Parse Error|Risky' | ForEach-Object { $_.Line.Trim() } | Select-Object -First 8
  "$name exit=$code :: " + ($summary -join ' | ')
}
