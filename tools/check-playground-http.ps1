# Run from the repository root: rtk proxy powershell -File tools/check-playground-http.ps1
$ErrorActionPreference = 'Stop'
$workspacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $PSScriptRoot 'smoke-playground-http.R'
$rscriptPath = (Get-Command Rscript -ErrorAction Stop).Source
$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
$process = $null
try {
    $process = Start-Process -FilePath $rscriptPath -ArgumentList @('--vanilla', 'tools/smoke-playground-http.R') -WorkingDirectory $workspacePath -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $response = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) { throw 'The playground server exited before its HTTP smoke check.' }
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:18199' -UseBasicParsing -TimeoutSec 1
            break
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if ($null -eq $response -or $response.StatusCode -ne 200 -or -not $response.Content.Contains('Use simulated user A') -or -not $response.Content.Contains('Run native call')) {
        throw 'Playground HTTP smoke failed.'
    }
    Write-Output 'HTTP 200: offline app and simulated authorization controls rendered.'
} finally {
    if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
}
