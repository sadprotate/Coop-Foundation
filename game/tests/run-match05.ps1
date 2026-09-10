param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$Node = 'node',
    [int]$Port = 18805
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$gamePath = Join-Path $projectRoot 'game'
$serverPath = Join-Path $projectRoot 'server\server.mjs'
$testDirectory = Join-Path $projectRoot ('test-results\match05-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
$clients = @()
$serverProcess = $null
$oldPort = $env:PORT
$oldHost = $env:HOST
$oldAppData = $env:APPDATA
try {
    $env:PORT = [string]$Port
    $env:HOST = '127.0.0.1'
    $serverProcess = Start-Process -FilePath $Node -ArgumentList @('"' + $serverPath + '"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDirectory 'server.log') -RedirectStandardError (Join-Path $testDirectory 'server-error.log')
    $deadline = (Get-Date).AddSeconds(12)
    $healthy = $false
    do {
        try { $healthy = (Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1).ok -eq $true }
        catch { Start-Sleep -Milliseconds 200 }
    } until ($healthy -or (Get-Date) -gt $deadline -or $serverProcess.HasExited)
    if (-not $healthy) { throw "Test server did not start. See $testDirectory" }
    foreach ($role in @('host', 'guest1', 'guest2', 'guest3')) {
        $profile = Join-Path $testDirectory "$role-profile"
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        $env:APPDATA = $profile
        $log = Join-Path $testDirectory "$role.log"
        $displayArguments = @('--headless')
        if ($role -eq 'host') { $displayArguments = @('--position', '-10000,-10000', '--resolution', '1280x800') }
        $arguments = $displayArguments + @('--path', ('"' + $gamePath + '"'), '--log-file', ('"' + $log + '"'), '--script', 'tests/match05_online.gd', '--', "--role=$role", "--server=ws://127.0.0.1:$Port/ws", ('"--directory=' + $testDirectory + '"'), ('"--expected-user-root=' + $profile + '"'))
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDirectory "$role-stdout.log") -RedirectStandardError (Join-Path $testDirectory "$role-stderr.log")
        $clients += [PSCustomObject]@{ Role = $role; Process = $process; Log = $log }
        Start-Sleep -Milliseconds 200
    }
    Write-Output "Match integration running. Logs: $testDirectory"
    $runDeadline = (Get-Date).AddSeconds(195)
    do {
        Start-Sleep -Milliseconds 500
        $running = @($clients | Where-Object { -not $_.Process.HasExited })
        $failedEarly = @($clients | Where-Object { $_.Process.HasExited -and $_.Process.ExitCode -ne 0 })
        if ($failedEarly.Count -gt 0) { break }
    } until ($running.Count -eq 0 -or (Get-Date) -gt $runDeadline)
    $failed = $false
    foreach ($client in $clients) {
        if (-not $client.Process.HasExited) { $failed = $true }
        $output = if (Test-Path -LiteralPath $client.Log) { Get-Content -LiteralPath $client.Log -Raw } else { '' }
        $output -split "`n" | Where-Object { $_ -match '^MATCH05 RESULT|^MATCH05 .*FAIL|^SCRIPT ERROR' } | Write-Output
        $gameErrors = $output -split "`n" | Where-Object { $_ -match '^(SCRIPT ERROR|ERROR):' -and $_ -notmatch 'Failed to read the root certificate store' }
        if ($gameErrors) { Write-Output $gameErrors }
        if (-not $client.Process.HasExited -or $client.Process.ExitCode -ne 0 -or $output -notmatch "MATCH05 RESULT $($client.Role): \d+ checks, 0 failures" -or $gameErrors) { $failed = $true }
    }
    Write-Output "Logs and captures: $testDirectory"
    Write-Output 'Scope: four actual Godot/Main/Net clients on this PC; separate-network internet testing remains separate.'
    if ($failed) { throw 'Four-client match integration failed. Inspect the per-client logs.' }
} finally {
    foreach ($client in $clients) { if (-not $client.Process.HasExited) { Stop-Process -Id $client.Process.Id } }
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id }
    $env:PORT = $oldPort
    $env:HOST = $oldHost
    $env:APPDATA = $oldAppData
}
