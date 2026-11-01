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
