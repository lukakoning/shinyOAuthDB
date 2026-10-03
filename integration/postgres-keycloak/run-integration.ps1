param(
    [switch]$Keep,
    [switch]$SkipBuild,
    [switch]$Playground
)
$ErrorActionPreference = 'Stop'
$fixturePath = [System.IO.Path]::GetFullPath($PSScriptRoot)
$composePath = Join-Path $fixturePath 'compose.yml'
$project = 'shinyoauthdb-postgres-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$composeArguments = @('compose', '--project-name', $project, '--file', $composePath)
$started = $false
$result = 1

function Invoke-FixtureCompose {
    param([string[]]$Arguments)
    & docker @composeArguments @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'The Docker Compose fixture command failed.' }
}

try {
    & docker version --format '{{.Server.Version}}'
    if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop with Linux containers must be running.' }
    Invoke-FixtureCompose -Arguments @('config', '--quiet')
    if (-not $SkipBuild) { Invoke-FixtureCompose -Arguments @('build', 'postgres', 'test-runner') }
    $started = $true
    Invoke-FixtureCompose -Arguments @('up', '--detach', '--wait', '--wait-timeout', '180', 'postgres')
    $testArguments = @('run', '--rm', '--no-deps', 'test-runner')
    if ($Playground) {
        $testArguments += @('Rscript', 'integration/postgres-keycloak/run-tests.R', '--playground')
    }
    & docker @composeArguments @testArguments
    $result = $LASTEXITCODE
    if ($result -ne 0 -and -not $Playground) {
        Write-Output 'Integration failed. Review the test output above; raw authentication logs are not exported.'
    }
} finally {
    if ($started -and -not $Keep) {
        & docker @composeArguments down --volumes --remove-orphans
        if ($LASTEXITCODE -ne 0 -and $result -eq 0) { $result = 1 }
    } elseif ($started) {
        Write-Output "Kept fixture project: $project"
        Write-Output "Cleanup: docker compose --project-name $project --file integration/postgres-keycloak/compose.yml down --volumes"
    }
}
exit $result
