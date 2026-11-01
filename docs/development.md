# Package development

shinyOAuthDB supplies user credentials to existing R clients. Keep sign-in
and token renewal in shinyOAuth, queries in the database package, and result
storage in the Shiny app.

## Finding the code

Each `R/backend__*.R` file contains one platform's connection helpers,
OAuth presets, and driver options. Shared code handles authorization checks
(`authorization.R`), connection reuse and cleanup (`session.R`), and native
API calls (`api.R`).

When adding a backend, prefer a public token or callback argument in an
existing client. Return its native connection or results. Check that a
missing or expired credential cannot switch to the hosting environment's
account. Keep backend-specific settings in the backend file.

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
tests also exercise the getting-started app and connection snippets through
Shiny. Keep these examples small enough to read as a whole.

## Live checks

See [integration tests](../tests/integration/README.md) for cloud fixtures
and the local PostgreSQL/Keycloak browser test. The
[Fabric playground](../playground/fabric/README.md) uses an existing sandbox
with its own start and pause workflow.

Record versions, results, and limits in [validation.md](validation.md).
