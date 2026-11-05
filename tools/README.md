Run the full package validation from the repository root:

```sh
Rscript --vanilla tools/test-validation.R
Rscript --vanilla tools/test-docs.R
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

Coverage runs installed-package tests. Repository-only example checks can skip
in that context; the required source suite already checks them without skips.
The package-check lane disables native PostgreSQL OAuth. Its C coverage is the
unsupported-platform branch, not evidence for the working libpq hook. Use the
PostgreSQL Docker integration for that implementation.
