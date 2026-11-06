Run the full package validation from the repository root:

```sh
Rscript --vanilla tools/test-validation.R
Rscript --vanilla tools/test-docs.R
Rscript --vanilla tools/test-integration.R
Rscript --vanilla tools/check-package.R
Rscript --vanilla tools/check-coverage.R
```

With Docker running, `Rscript tools/check-clickhouse-parameters.R` checks
DateTime, DateTime64, nullable timestamps, and timezone conversion against a
real ClickHouse engine. It runs local SQL without a Cloud account or JWT
configuration. Set `OAUTHDB_CLICKHOUSE_TEST_IMAGE` to use another Docker image.

Each script accepts additional R library directories as trailing arguments.
The documentation checker uses rmarkdown and Pandoc to resolve rendered section
anchors and local file links, including every integration guide. It parses R
examples without executing them.
The scripts use an isolated temporary package installation; they do not install
dependencies into your normal library. Install the package's Imports and
Suggests, plus pkgbuild, rcmdcheck and covr, before running them.

The integration harness requires the complete named scenario set and exact
TLS, permission, and data check names. `test-integration.R` verifies that empty
or incomplete runs cannot pass. Browser snapshots distinguish read attempts
from successful reads; PostgREST also counts reads at its real HTTPS proxy.

`check-package.R` checks dependency availability and declared minimum versions,
then runs the source suite. Any failure, error, warning, skipped scenario or
empty test run fails validation. The subsequent R CMD check must have zero
errors, warnings and notes. `test-validation.R` verifies that missing/outdated
dependencies and incomplete results really are rejected.

Results are retained in the ignored `.validation/` directory:

- `test-summary.json` and `test-results.csv`: source scenarios and assertions.
- `dependency-versions.json`: versions used by the source tests.
- `package-check.json`: R CMD check errors, warnings and notes.
- `coverage.rds`, `coverage-lines.csv` and `coverage-summary.json`: coverage
  details with separate R and C line counts.

The package-check workflow uploads these artifacts separately for Windows and
Linux. Linux also collects coverage. It installs all direct dependencies and
pins shinyOAuth to the same revision as the local integration workflows.

The minimum-backends workflow installs brickster 0.2.14, fabricQueryR 1.0.1,
RTrino 0.1.0, or odbc 1.4.2 in separate jobs and runs the full source suite.
The odbc job uses R 4.5 because its configure script requires `CXX11`, which
R 4.6 removed. The other jobs use the current R release.
To reproduce a job with that SDK installed in an isolated library, run:

```sh
Rscript --vanilla tools/check-backend-minimum.R brickster path/to/minimum-sdk-library
```

The script requires the exact version declared in `DESCRIPTION` and all other
test dependencies. It rejects skips, warnings, errors, and failed assertions.
Counts and installed versions are retained under
`.validation/minimum-backends/<package>/`.

Coverage runs installed-package tests. Repository-only example checks can skip
in that context; the required source suite already checks them without skips.
The package-check lane disables native PostgreSQL OAuth. Its C coverage is the
unsupported-platform branch, not evidence for the working libpq hook. Use the
PostgreSQL Docker integration for that implementation.
