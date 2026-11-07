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

The [R-CMD-check workflow](../.github/workflows/R-CMD-check.yaml) runs the source
suite and the standard R package check action on Windows, macOS and Linux.
Linux also checks R devel and oldrel-1. The
[quality workflow](../.github/workflows/quality.yaml) checks documentation and
validation tools on Windows and Linux, runs Air and Jarl, and collects coverage
in a separate Linux job. Both run for pull requests and pushes to `main` or
`master`, and support manual dispatch. See the [workflow map](../.github/README.md).

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

## Documentation website and packaged demos

Run `pkgdown::build_site()` to preview the website. `_pkgdown.yml` groups the
database articles and reference pages. Output goes to ignored `_site/`, so
building the website preserves the developer notes in `docs/`.

The [website workflow](../.github/workflows/pkgdown.yaml) builds pull requests
and deploys pushes to the default branch. In repository **Settings > Pages**,
select **GitHub Actions** as the publishing source before the first deployment.
The public URL is `https://lukakoning.github.io/shinyOAuthDB/`.

`inst/docker/` contains the installed Docker contexts. `oauth_db_demo()` copies
them into a writable cache and starts Compose without a source checkout.
The app containers install the pinned revisions in `inst/docker/install.R`;
update those pins when a newer runtime is needed, then verify browser sign-in
and the row policy for Alice and Bob. Run `action = "files"` from an installed
package to check that the demo doesn't depend on repository-only files.
`Rscript --vanilla tools/check-demos.R postgres` automates the installed-package
and browser check; substitute another demo name to check it too.

Keep the README's app in sync with `inst/examples/postgres/app.R`. Displayed
app examples should focus on sign-in, a database helper and a query. Keep
the styled layouts and diagnostic panels in the runnable demo templates
under `inst/docker/` and `inst/cloud-demo/`.

Resolve `connection <- con()` before calling a DBI method. Passing `con()`
directly can turn Shiny's wait-for-sign-in signal into a visible method
dispatch error. The documented-app tests check this signed-out state.

Each backend guide should introduce the source, show where settings come
from, present one small complete app and then explain server setup and
advanced options. Put shared registration terminology in
`vignettes/oauth-setup.Rmd`.

## Selected mutation checks

Run `Rscript --vanilla tools/check-mutations.R` with the full test dependencies
installed. It first requires a passing baseline, then changes one guard at a
time in a temporary copy: provider retirement, Trino TLS verification, Trino
pagination origins, and PostgREST mutation retries. Each change must produce
failed assertions in its named regression test. An error, skipped scenario,
invalid patch or passing mutant fails validation. Warnings caused by a mutant
are recorded; they cannot substitute for a failed assertion.

Mutation testing does not run in GitHub Actions. Local results are retained under
`.validation/mutations/`. This checks four specific protections; it is not a
package-wide mutation score. Your checkout is never modified by the runner.

You can also run generated AST mutations locally using
[`mutator`](https://prl-prg.github.io/mutator/) 0.3.0. Install it in your
development library, then choose a campaign:

```sh
Rscript --vanilla tools/check-mutator.R transport
Rscript --vanilla tools/check-mutator.R lifecycle
Rscript --vanilla tools/check-mutator.R bigquery
Rscript --vanilla tools/check-mutator.R trino
Rscript --vanilla tools/check-mutator.R odbc
Rscript --vanilla tools/check-mutator.R all
```

The [November audit](mutation-testing.md) records sampled outcomes, verified
test improvements and remaining priorities.

Additional arguments are dependency-library paths. The runner copies source
files and repository fixtures into a temporary directory, checks a strict
baseline, and lets mutator generate the edits. It uses coverage-guided test
selection, a fixed seed and isolated mutant copies. Each report records the
source hashes, tool version, selected tests and sampling settings.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `OAUTHDB_MUTATOR_LIMIT` | `100` | Maximum sampled mutants |
| `OAUTHDB_MUTATOR_CORES` | `2` | Concurrent test processes |
| `OAUTHDB_MUTATOR_SEED` | `20261104` | Reproducible sampling |
| `OAUTHDB_MUTATOR_TIMEOUT` | `240` | Seconds allowed per mutant |
| `OAUTHDB_MUTATOR_OUTPUT` | `.validation/mutator` | Report parent directory |

Local campaign reports include baseline assertion counts, mutation summaries,
individual outcomes, original R files and the sampled mutant sources. A missing
baseline, failed/skipped baseline test or incomplete campaign fails the run. Survivors
remain in the report for review; there is no perfect-score gate or blanket
exclusion of surviving lines. The curated runner requires its named guard checks.

Mutator's `KILLED` category includes execution errors as well as test failures;
`HANG` is reported separately. Inspect a survivor's edit and add a behavioral
regression when it changes the package contract. A harmless equivalent change
does not justify an implementation-specific assertion. External/LLM equivalence
detection is disabled. These campaigns mutate R source; the native C OAuth hook
has its separate PostgreSQL Docker coverage run.

The Trino campaign includes native option and TLS policy tests. The ODBC
campaign covers SQL Server, Redshift, Snowflake, StarRocks and Databricks;
it includes provider configuration tests as well as connection tests.
These use mocked network responses and native connection boundaries. Use
the separate Docker integration lanes to validate actual driver/server
behavior.

## Compatibility lanes

The [compatibility workflow](../.github/workflows/compatibility.yaml) runs
the core authorization, lifecycle, SQLite and HTTP API tests on R 4.1.0 and
the current R release. It requires exactly DBI 1.2.0, httr2 1.2.0, Shiny 1.8.1
and curl 6.4.0. The R 4.1.0 job uses testthat 3.2.0; the current R job uses
the current testthat release. It fails if the pinned dependency
versions drift, if tests are skipped, or if any assertion, error or warning
fails validation. Versions and counts are retained in `.validation/minimum/`.

The same workflow's minimum backend matrix
tests actual SDK releases in four separate jobs: brickster 0.2.14,
fabricQueryR 1.0.1, RTrino 0.1.0, and odbc 1.4.2. The odbc job uses R 4.5
because its configure script requires `CXX11`, which R 4.6 removed; the other
jobs use the current R release. Each job installs its selected
SDK at the declared minimum and runs the full source suite with the other test
dependencies. The runner checks the installed version against `DESCRIPTION`
before testing, so an upgraded SDK cannot silently pass a minimum-version job.
Results and installed versions are retained in `.validation/minimum-backends/`.
These jobs use mocked platform responses and native driver boundaries; the
Docker lanes cover their real server fixtures.

Run `Rscript --vanilla tools/check-backend-minimum.R brickster path/to/library`
to reproduce a backend job locally. These jobs test one SDK minimum at a time;
they use newer core dependencies than the R 4.1.0 lane when an SDK needs them.

Routine package and Docker workflows use the same pinned shinyOAuth revision.
Its independent upstream job runs the full tests and R CMD check weekly against
shinyOAuth's current master and updated CRAN packages. Its failures identify upstream changes separately
from the reproducible pull-request lanes. All of these jobs can run in
parallel, and none provisions cloud resources.
