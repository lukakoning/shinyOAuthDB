# Package development

shinyOAuthDB connects a user's sign-in to database and platform functions.
shinyOAuth handles login and token renewal; the database package runs queries.
The Shiny app manages any results it saves.

## Finding the code

Each `R/backend__*.R` file contains one platform's connection helpers,
OAuth presets, and driver options. Shared code checks authorizations
(`authorization.R`), manages connections (`session.R`), and prepares
API calls (`api.R`).

When adding a backend, prefer a public token or callback argument in an
existing client. Return that package's connection or result. Check that
missing or expired credentials don't cause the client to use the hosting
environment's account. Keep platform settings in the backend file.

## Local checks

Run from the repository root with the dependencies in `DESCRIPTION` installed:

```sh
Rscript --vanilla tools/check-package.R
Rscript --vanilla tools/check-docs.R
```

The package checker installs into a temporary library, runs the test suite,
builds the vignettes, and runs `R CMD check --no-manual`. Supply an extra
dependency library as a positional argument if needed. These checks use
mocked cloud responses; they do not start browser sign-in or cloud resources.

The [package-checks workflow](../.github/workflows/package-checks.yaml) runs
both commands on Windows and Linux with the current R release. It runs for
pull requests and pushes to `main` or `master`; you can also start it manually
from GitHub Actions.

After editing roxygen comments, regenerate help pages:

```r
roxygen2::roxygenise()
```

The documentation check parses R examples and checks local links. Regression
tests also construct each source guide's app and check that queries wait
for sign-in. Each guide should work on its own: explain what the app can
do, show a complete example with ordinary queries, then introduce advanced
options. Keep sign-in setup and query examples together.

## Live checks

See [integration tests](../tests/integration/README.md) for cloud fixtures
and the local PostgreSQL/Keycloak browser test. The
[Fabric playground](../playground/fabric/README.md) uses an existing sandbox
with its own start and pause workflow.

Record versions, results, and limits in [validation.md](validation.md).

## Selected mutation checks

Run `Rscript --vanilla tools/check-mutations.R` with the full test dependencies
installed. It first requires a passing baseline, then changes one guard at a
time in a temporary copy: provider retirement, Trino TLS verification, Trino
pagination origins, and PostgREST mutation retries. Each change must produce
failed assertions in its named regression test. An error, skipped scenario,
invalid patch or passing mutant fails validation. Warnings caused by a mutant
are recorded; they cannot substitute for a failed assertion.

The independent [mutation workflow](../.github/workflows/mutation-checks.yaml)
runs weekly and on manual dispatch. Results are retained under
`.validation/mutations/`. This checks four specific protections; it is not a
package-wide mutation score. Your checkout is never modified by the runner.

## Compatibility lanes

The [minimum workflow](../.github/workflows/minimum-compatibility.yaml) runs
the core authorization, lifecycle, SQLite and HTTP API tests on R 4.1.0 and
the current R release. It requires exactly DBI 1.2.0, httr2 1.2.0, Shiny 1.8.1
and testthat 3.2.0, with httr2's curl 6.4.0 dependency floor. It fails if those
versions drift, if tests are skipped, or if any assertion, error or warning
fails validation. Versions and counts are retained in `.validation/minimum/`.
Optional platform SDKs run in the full package and Docker lanes; their current
versions can require newer dependencies than this core configuration.

Routine package and Docker workflows use the same pinned shinyOAuth revision.
The independent [upstream workflow](../.github/workflows/upstream-compatibility.yaml)
runs the full tests and R CMD check weekly against shinyOAuth's current master
and updated CRAN packages. Its failures identify upstream changes separately
from the reproducible pull-request lanes. All of these workflows can run in
parallel, and none provisions cloud resources.
