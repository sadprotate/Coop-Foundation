param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$Node = 'node',
    [int]$Port = 18787,
    [switch]$CaptureLobby
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$gamePath = Join-Path $projectRoot 'game'
$serverPath = Join-Path $projectRoot 'server\server.mjs'
$testDirectory = Join-Path $projectRoot ('test-results\combat-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
$coord = Join-Path $testDirectory 'room-code.txt'
$clients = @()
$serverProcess = $null
$oldPort = $env:PORT
$oldHost = $env:HOST
$oldAppData = $env:APPDATA
try {
	# Keep test-created preferences/logs inside the selected workspace.
	$testProfile = Join-Path $testDirectory 'profile'
	New-Item -ItemType Directory -Path $testProfile -Force | Out-Null
	$env:APPDATA = $testProfile
    $env:PORT = [string]$Port
    $env:HOST = '127.0.0.1'
    $serverProcess = Start-Process -FilePath $Node -ArgumentList @('"' + $serverPath + '"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDirectory 'server.log') -RedirectStandardError (Join-Path $testDirectory 'server-error.log')
    $deadline = (Get-Date).AddSeconds(12)
    $healthy = $false
    do {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1
            $healthy = $health.ok -eq $true
        } catch { Start-Sleep -Milliseconds 200 }
    } until ($healthy -or (Get-Date) -gt $deadline -or $serverProcess.HasExited)
    if (-not $healthy) { throw "Test server did not start. See $testDirectory" }
    foreach ($role in @('host', 'guest1', 'guest2', 'guest3')) {
        $log = Join-Path $testDirectory "$role.log"
        $displayArguments = @('--headless')
        if ($CaptureLobby -and $role -eq 'host') { $displayArguments = @('--position', '-10000,-10000') }
        $arguments = $displayArguments + @('--path', ('"' + $gamePath + '"'), '--log-file', ('"' + $log + '"'), '--script', 'tests/lobby_client.gd', '--', "--role=$role", "--server=ws://127.0.0.1:$Port", ('"--coord=' + $coord + '"'))
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDirectory "$role-stdout.log") -RedirectStandardError (Join-Path $testDirectory "$role-stderr.log")
        $clients += [PSCustomObject]@{ Role = $role; Process = $process; Log = $log }
        Start-Sleep -Milliseconds 150
    }
    $failed = $false
    foreach ($client in $clients) {
        if (-not $client.Process.WaitForExit(135000)) { throw "Client timed out: $($client.Role)" }
        $output = Get-Content -LiteralPath $client.Log -Raw
        $result = $output -split "`n" | Where-Object { $_ -match 'LOBBY_TEST.*(PASS|FAIL)' }
        Write-Output $result
        if ($client.Process.ExitCode -ne 0 -or $output -notmatch "LOBBY_TEST $($client.Role) PASS") { $failed = $true }
    }
    Write-Output "Logs: $testDirectory"
    Write-Output 'Scope: four real Godot processes on this PC. Internet testing remains separate.'
    if ($failed) { throw 'At least one lobby client test failed.' }
} finally {
    foreach ($client in $clients) {
        if (-not $client.Process.HasExited) { Stop-Process -Id $client.Process.Id }
    }
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id }
    $env:PORT = $oldPort
    $env:HOST = $oldHost
    $env:APPDATA = $oldAppData
}
