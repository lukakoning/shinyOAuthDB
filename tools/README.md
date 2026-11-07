See the [CI workflow map](../.github/README.md) for job groups, platforms and
triggers. Run package validation from the repository root:

```sh
Rscript --vanilla tools/test-validation.R
Rscript --vanilla tools/test-docs.R
Rscript --vanilla tools/test-integration.R
Rscript --vanilla tools/test-provenance.R
Rscript --vanilla tools/test-live.R
Rscript --vanilla tools/check-package.R
Rscript --vanilla tools/check-duckdb.R
Rscript --vanilla tools/check-duckdb-oauth.R
Rscript --vanilla tools/check-libsql-oauth.R
Rscript --vanilla tools/check-cratedb-oauth.R
Rscript --vanilla tools/check-opensearch-oauth.R
Rscript --vanilla tools/check-coverage.R
```

With Docker running, `check-cratedb-oauth.R` exercises native CrateDB JWT
validation, user privileges, exact results and verified TLS. It also checks
timeouts and dropped write responses using the
[CrateDB fixture](../integration/cratedb-oauth/README.md).

`check-duckdb.R` downloads the matching Quack extension and starts a real
loopback DuckDB server. It checks DBI/dbplyr queries, token replacement,
server rejection, TLS enforcement and cleanup using synthetic authorizations.
It does not test an identity provider or quack_oauth's token validation.
Set `OAUTHDB_DUCKDB_TEST_PORT` if the default port 19494 is occupied.

With Docker running, `check-duckdb-oauth.R` also exercises real JWT validation
and server policies through `quack_oauth`, including verified TLS, private
CA trust, and certificate hostname checks. It generates disposable tokens
and certificates in the [DuckDB OAuth fixture](../integration/duckdb-oauth/README.md).

`check-libsql-oauth.R` runs a real libSQL server behind verified HTTPS with
Ed25519-signed user tokens. It checks database permissions, native SQLite
values, token changes, TLS failures, and dropped/delayed write responses.
See the [libSQL fixture](../integration/libsql-oauth/README.md) for scope
and token compatibility. It needs Docker and no production credentials.

With Docker running, `check-opensearch-oauth.R` checks native OpenSearch
Security JWT authentication, document and field permissions, Query DSL,
aggregations, SQL parameters and TLS through the public helper. The
[fixture](../integration/opensearch-oauth/README.md) generates disposable
keys and tokens. Set `OAUTHDB_OPENSEARCH_TEST_IMAGE` or
`OAUTHDB_OPENSEARCH_TEST_PORT` to override its image or loopback port.

With Docker running, `Rscript tools/check-clickhouse-parameters.R` checks
DateTime, DateTime64, nullable timestamps, and timezone conversion against a
real ClickHouse engine. It runs local SQL without a Cloud account or JWT
configuration. Set `OAUTHDB_CLICKHOUSE_TEST_IMAGE` to use another Docker image.
The integration workflow runs this real-engine parameter check on Linux.
`Rscript tools/check-clickhouse-http.R` additionally checks the public API
helper, real HTTPS, typed results, local grants and dropped/delayed write
responses in an isolated [Docker fixture](../integration/clickhouse-http/README.md).

Each script accepts additional R library directories as trailing arguments.
The documentation checker uses rmarkdown and Pandoc to resolve rendered section
anchors and local file links, including every integration guide. It parses R
examples without executing them.
The scripts use an isolated temporary package installation; they do not install
dependencies into your normal library. Install the package's Imports and
Suggests, plus pkgbuild, rcmdcheck and covr, before running them.

`Rscript --vanilla tools/check-demos.R postgres` installs the package in a
temporary library, starts its packaged Docker demo from outside the checkout
and checks real browser sign-in for Alice and Bob, row permissions, sign-out
and the stop button. It needs Docker, Chrome, pkgbuild, callr and chromote.
Use `postgrest`, `trino`, `starrocks`, `duckdb`, `libsql`, `cratedb` or
`opensearch` to check another demo; run one at a
time because they use the same loopback ports. The
[demo workflow](../.github/workflows/demos.yaml) runs each
in a separate job and retains logs under `.validation/demos/`.
The DuckDB, libSQL and CrateDB examples share a read-only table between
accounts; OpenSearch filters documents per user. These four checks also
verify the current account display and database rejection of writes.

Pass `local` after the database name to check a host R app backed by Docker:

```sh
Rscript --vanilla tools/check-demos.R postgrest local
```

This also verifies that Docker isn't running the Shiny app and that a saved
edit to the local app appears in the next browser session. Local checks use
the host R library; install the database-specific dependencies listed in
the local demo guide. CI checks six local variants alongside the eight
Docker apps. Native PostgreSQL needs the matching Linux/libpq 18 build;
StarRocks needs the native MySQL ODBC driver and plugin.

For the guided cloud demo, run:

```sh
Rscript --vanilla tools/check-cloud-demo.R fabric
```

This starts Keycloak in Docker and the generated cloud app in native R.
Chrome signs in as Alice and Bob. Select `databricks` (the default), `fabric`,
`bigquery`, `snowflake`, `azure-sql`, `azure-postgres`, `redshift` or `clickhouse`.
Cloud SQL/API operations are mocked; OAuth, the installed app and its native
R process are real. The test verifies no implicit SQL, per-user output,
sign-out cleanup and credential-free generated files. Native database
drivers and real cloud registrations remain outside this fixture's scope.
The demo workflow runs all eight without cloud credentials.

The integration harness requires the complete named scenario set and exact
TLS, permission, and data check names. `test-integration.R` verifies that empty
or incomplete runs cannot pass. Browser snapshots distinguish read attempts
from successful reads; PostgREST also counts reads at its real HTTPS proxy.
Integration artifacts include a Git revision when available, a SHA-256
manifest of package/test/fixture sources, fixture version, dependency versions,
and named scenario results. The content hash distinguishes dirty runs even
when the package version and Git revision are unchanged. Generated results
and compiled objects are excluded from the manifest.
`test-live.R` checks the public Databricks/Fabric routes with the installed
SDKs and synthetic authorization, plus the cloud runner's identity, denial,
replacement and cleanup rules. It makes no cloud requests.

Mutation testing is optional local tooling and is not run by GitHub Actions.
Run `Rscript --vanilla tools/test-mutations.R` to check its policy, or use
`check-mutations.R` and `check-mutator.R` for local campaigns. A new survivor
fails the campaign; a timeout remains inconclusive and cannot be allowlisted.
Only a reviewed equivalent survivor with the exact profile, original-source
SHA-256, mutant SHA-256 and explanation in `mutation-baseline.csv` is accepted.
The initial baseline has no exceptions. Review the saved original/mutant files
and add a useful regression before considering an equivalence exception.

`check-package.R` checks dependency availability and declared minimum versions,
then runs the source suite. Any failure, error, warning, skipped scenario or
empty test run fails validation. Pass `--tests-only` to stop after that suite;
CI uses this option before the standard `check-r-package` action. The subsequent
R CMD check must have zero
errors, warnings and notes. `test-validation.R` verifies that missing/outdated
dependencies and incomplete results really are rejected.

Results are retained in the ignored `.validation/` directory:

- `test-summary.json` and `test-results.csv`: source scenarios and assertions.
- `dependency-versions.json`: versions used by the source tests.
- `package-check.json`: R CMD check errors, warnings and notes.
- `coverage.rds`, `coverage-lines.csv` and `coverage-summary.json`: coverage
  details with separate R and C line counts.

The R-CMD-check workflow uploads source-test artifacts for each OS/R combination
and retains the standard action's check logs. The quality workflow collects
coverage in an independent Linux job. Both install all direct dependencies and
pin shinyOAuth to the same revision as the local integration workflows.

The compatibility workflow installs brickster 0.2.14, fabricQueryR 1.0.1,
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
