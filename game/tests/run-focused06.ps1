param([Parameter(Mandatory=$true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$target = Join-Path $project ('test-results/focused06-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $target | Out-Null
$previousAppData = $env:APPDATA
try {
    foreach ($testName in @('movement05','world05','bindings','match05')) {
        $profile = Join-Path $target ($testName + '-profile')
        New-Item -ItemType Directory -Force -Path $profile | Out-Null
        $env:APPDATA = $profile
        $log = Join-Path $target ($testName + '.log')
        $arguments = @('--position','-10000,-10000','--path',('"' + (Join-Path $project 'game') + '"'),'--log-file',('"' + $log + '"'),'--script',('tests/' + $testName + '.gd'),'--',('"--expected-user-root=' + $profile + '"'),('"--screenshots=' + (Join-Path $target 'screenshots') + '"'))
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(45000)) { Stop-Process -Id $process.Id; throw "$testName timed out" }
        $content = Get-Content -LiteralPath $log -Raw
        $content -split "`n" | Where-Object {$_ -match 'RESULT|FAIL|SCRIPT ERROR'} | Write-Output
        if ($process.ExitCode -ne 0 -or $content -match 'SCRIPT ERROR|FAIL:' -or $content -notmatch 'RESULT') { throw "$testName failed: $log" }
    }
    Write-Output "Focused results: $target"
} finally { $env:APPDATA = $previousAppData }
