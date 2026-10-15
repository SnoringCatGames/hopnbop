# H37 social: run each social GUT file alone with a throwaway APPDATA.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\lsl\Repositories\hopnbop'
$probe = Join-Path $root '.claude\probes\H37\h37-social'
$env:APPDATA = Join-Path $probe 'appdata'
$godot = 'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe'
$files = @(
  'test_friends_api_client', 'test_friends_notification_contract',
  'test_friends_notification_poller', 'test_friends_poller_lifecycle',
  'test_party_api_client', 'test_party_leave_contract',
  'test_party_manager', 'test_party_matchmaking_context')
foreach ($f in $files) {
  $log = Join-Path $probe "gut\$f.log"
  & $godot --headless -s --path $root addons/gut/gut_cmdln.gd `
    "-gtest=res://test/unit/platform/$f.gd" -gexit *> $log
  $code = $LASTEXITCODE
  $sum = Select-String -Path $log -Pattern '^(Passing|Failing|Pending|Tests|Asserts)\s|Nothing was run|---- All tests passed|SCRIPT ERROR|Parse Error' |
    ForEach-Object { $_.Line.Trim() }
  "{0} exit={1} :: {2}" -f $f, $code, ($sum -join ' | ')
}
