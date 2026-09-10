param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [switch]$Render,
    [int]$Width = 1280,
    [int]$Height = 800
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$gamePath = Join-Path $projectRoot 'game'
$variant = if ($Render) { "render-$Width-$Height" } else { 'headless' }
$testDirectory = Join-Path $projectRoot ('test-results\smoke-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $variant)
$testProfile = Join-Path $testDirectory 'profile'
$log = Join-Path $testDirectory 'smoke.log'
New-Item -ItemType Directory -Path $testProfile -Force | Out-Null
$settingsDirectory = Join-Path $testProfile 'Godot\app_userdata\Co-op Foundation'
New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
$settingsFile = Join-Path $settingsDirectory 'settings.cfg'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\settings.cfg') -Destination $settingsFile
$settingsBefore = (Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256).Hash
$oldAppData = $env:APPDATA
$process = $null
try {
    $env:APPDATA = $testProfile
    $displayArguments = @('--headless')
    if ($Render) { $displayArguments = @('--position', '-10000,-10000', '--resolution', "${Width}x${Height}") }
    $arguments = $displayArguments + @('--path', ('"' + $gamePath + '"'), '--log-file', ('"' + $log + '"'), '--script', 'tests/smoke.gd', '--', ('"--expected-user-root=' + $testProfile + '"'))
    if ($Render) { $arguments += ('"--screenshots=' + (Join-Path $testDirectory 'screenshots') + '"') }
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDirectory 'stdout.log') -RedirectStandardError (Join-Path $testDirectory 'stderr.log')
    if (-not $process.WaitForExit(45000)) { throw "Smoke test timed out. See $testDirectory" }
    $output = Get-Content -LiteralPath $log -Raw
    $result = $output -split "`n" | Where-Object { $_ -match '^SMOKE RESULT:' }
    Write-Output $result
    Write-Output "Logs: $testDirectory"
    $gameErrors = $output -split "`n" | Where-Object { $_ -match '^(SCRIPT ERROR|ERROR):' -and $_ -notmatch 'Failed to read the root certificate store' }
    if ($gameErrors) { Write-Output $gameErrors }
    if ((Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256).Hash -ne $settingsBefore) { throw 'Smoke test did not restore its existing settings fixture exactly.' }
    Write-Output 'Settings fixture restored byte-for-byte in the isolated workspace profile.'
    if ($process.ExitCode -ne 0 -or $output -notmatch 'SMOKE RESULT: \d+ checks, 0 failures' -or $gameErrors) { throw 'Client smoke test failed.' }
} finally {
    if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    $env:APPDATA = $oldAppData
}
