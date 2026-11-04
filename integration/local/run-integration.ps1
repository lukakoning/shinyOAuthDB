param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('postgrest', 'trino', 'starrocks', 'minilake')]
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
        $builder = & docker context show
        if ($LASTEXITCODE -ne 0) { throw 'Reading the Docker context failed.' }
        & docker build --builder $builder --target runner --tag shinyoauthdb-local-runner:1 $PSScriptRoot
        if ($LASTEXITCODE -ne 0) { throw 'Building the shared test runner failed.' }
        # Use the context's built-in builder to consume the base image from CI.
        & docker build --builder $builder --target tls --tag shinyoauthdb-local-tls:1 $PSScriptRoot
        if ($LASTEXITCODE -ne 0) { throw 'Building the TLS initializer failed.' }
        if ($Backend -ne 'postgrest') {
            & docker build --builder $builder --target runner --tag "shinyoauthdb-${Backend}-runner:1" (Join-Path $root "integration/$Backend-keycloak")
            if ($LASTEXITCODE -ne 0) { throw 'Building the backend test runner failed.' }
        }
    }
    $services = @('database', 'tls-probe')
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
