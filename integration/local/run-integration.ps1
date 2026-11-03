param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('postgrest', 'trino', 'starrocks')]
    [string]$Backend,
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$env:OAUTHDB_FIXTURE = $Backend
$project = 'oauthdb-' + $Backend + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$compose = @('compose', '--project-name', $project, '--project-directory', $PSScriptRoot,
    '--file', (Join-Path $PSScriptRoot 'compose.yml'),
    '--file', (Join-Path $root "integration/$Backend-keycloak/compose.yml"))
function Invoke-Fixture {
    param([string[]]$Arguments)
    & docker @compose @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Local integration command failed.' }
}
try {
    Invoke-Fixture -Arguments @('config', '--quiet')
    if (-not $SkipBuild) {
        & docker build --target runner --tag shinyoauthdb-local-runner:1 $PSScriptRoot
        if ($LASTEXITCODE -ne 0) { throw 'Building the shared test runner failed.' }
        Invoke-Fixture -Arguments @('build')
    }
    $services = @('database')
    if ($Backend -eq 'postgrest') { $services += 'https' }
    try {
        Invoke-Fixture -Arguments (@('up', '--detach', '--wait', '--wait-timeout', '240') + $services)
    } catch {
        # This precedes browser login; never export authentication/query logs after tests.
        & docker @compose logs --tail 1000 database
        throw
    }
    Invoke-Fixture -Arguments @('run', '--rm', '--no-deps', 'test-runner')
} finally {
    & docker @compose down --volumes --remove-orphans
    if ($LASTEXITCODE -ne 0) { throw 'Local integration cleanup failed.' }
}
