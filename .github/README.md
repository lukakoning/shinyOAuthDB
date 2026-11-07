# Continuous integration

| Workflow | Checks | When it runs |
| --- | --- | --- |
| [R-CMD-check](workflows/R-CMD-check.yaml) | Source tests and standard `r-lib/actions/check-r-package` checks on macOS, Windows and Linux; Linux also tests R devel and oldrel-1 | Push, pull request, manual |
| [Quality](workflows/quality.yaml) | Air formatting, Jarl lint, documentation and validation-tool tests on Linux and Windows, plus an independent R/C coverage job | Push, pull request, manual |
| [Compatibility](workflows/compatibility.yaml) | R 4.1.0 and core dependency floors; four exact minimum backend SDK versions | Push, pull request, manual |
| [Integration](workflows/integration.yaml) | PostgreSQL native OAuth and coverage; Keycloak browser fixtures; real DuckDB, libSQL, CrateDB, OpenSearch and ClickHouse checks | Push, pull request, manual |
| [Demos](workflows/demos.yaml) | Eight packaged Docker apps, six host R variants and eight guided cloud demo browser fixtures | Relevant source changes, manual |
| [Documentation website](workflows/pkgdown.yaml) | Build pkgdown into `_site`; deploy the default branch to Pages | Push, pull request, manual |
| [Cloud acceptance](workflows/cloud-acceptance.yaml) | Delegated-user checks using protected environment credentials | Manual, enabled weekly schedule, enabled prerelease |

The compatibility workflow also checks the latest upstream shinyOAuth and
updated CRAN packages every Tuesday and on manual dispatch. Routine jobs pin
shinyOAuth to the same revision so upstream changes can be diagnosed separately.
Minimum-version jobs retain their existing R and SDK pins.

The R check matrix follows
[`usethis::use_github_action("check-standard")`](https://github.com/r-lib/actions/blob/v2/examples/check-standard.yaml).
It also requires a source test run with no skips or warnings, retains the
existing zero-note check policy, and uploads source counts and check logs.
Coverage and database fixtures run in separate jobs so a package-check failure
does not prevent them from running. Matrices use `fail-fast: false` to retain
results from every platform and backend.

Adapter jobs install core and fixture dependencies; the full SDK dependency
set is installed for package, coverage and minimum-SDK checks. Scheduled
upstream runs have their own concurrency group so a push cannot cancel them.

Air and Jarl use fixed tool versions with repository configuration. Run them
locally before committing:

```sh
air format .
jarl check .
```

Jarl's exceptions in `jarl.toml` cover enclosing-scope callback assignments,
deliberately invalid test inputs and externally sourced acceptance helpers.
Mutation testing is available through the scripts in `tools/`, and does not
run in GitHub Actions.

See [validation commands](../tools/README.md) for local checks and retained
artifacts. Cloud acceptance remains separate because it uses protected
credentials; the integration and demo fixtures use disposable local services.
