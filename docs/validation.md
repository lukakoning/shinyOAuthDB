# Validation record

## 4 November 2026: expanded local coverage

Checked on Windows 11 with R 4.5.1 and Docker Desktop Linux containers. The
minimum configuration also ran in an actual R 4.1.0 container, with DBI 1.2.0,
httr2 1.2.0, curl 6.4.0, Shiny 1.8.1 and testthat 3.2.0.

| Check | Result |
| --- | --- |
| Full source suite | 1,743 assertions across 170 scenarios |
| Minimum core suite on R 4.1.0 | 703 assertions across 75 scenarios |
| `R CMD check --no-manual` | Zero errors, warnings or notes |
| PostgreSQL 18.3 / libpq 18 / Keycloak browser suite | 132 assertions |
| PostgREST 16.5 / PostgreSQL 18.3 / Keycloak | 81 assertions |
| Trino 484 / RTrino 0.1.0 / Keycloak | 65 assertions |
| StarRocks 3.5.0 / MySQL Connector/ODBC 9.5.0 / Keycloak | 71 assertions |
| MiniLake / brickster 0.2.15 / Keycloak | 33 assertions |
| Selected mutation checks | All four changes fail assertions in their named regression tests |
| Documentation checker | 63 R blocks parse; 138 local links resolve |
| R line coverage | 1,279 / 1,349 lines: 94.81% |
| Linux native PostgreSQL C coverage | 172 / 184 lines: 93.48% |

The source, minimum and integration suites have zero failures, errors, warnings
or skipped scenarios. These results precede concurrent, uncommitted Fabric/ODBC
changes. The Windows C coverage tally describes the unsupported-platform stub;
the native figure above comes from the instrumented Linux/libpq 18 fixture.

The PostgreSQL negatives require actual server rejection of modified and
expired browser tokens, a wrong CA and a hostname mismatch. PostgREST tests
verify one committed write after HTTP 503, a dropped response and a timeout.
A real Keycloak refresh rejection retires local API access, and signing in as
another account recovers. StarRocks denies an existing connection after its
table-view grant is revoked and recovers after the grant is restored. The
PostgreSQL suite also terminates a real backend and reconnects as the same user.

MiniLake validates DBI/API compatibility, Arrow results and pagination across
100,000 rows. Its pinned image accepts every token, does not enforce grants,
and ignores named SQL parameters. Those limitations are recorded explicitly;
see the [fixture scope](../integration/minilake-keycloak/README.md).
No cloud workspace was provisioned or queried for this update.

Each platform has an independent Actions workflow. The new minimum lanes run
on pull requests; upstream compatibility and the selected mutation checks run
weekly or on manual dispatch. Workflow syntax was checked locally with
actionlint. New remote runs require these commits to be pushed.

Machine-readable results are in `.validation/` and each fixture's ignored
`.generated/` directory. See [development checks](development.md) and
[integration commands](../tests/integration/README.md) to reproduce them.

## 1 November 2026

Checked on Windows 11 with R 4.5.1, shinyOAuth 0.7.0, fabricQueryR 1.0.1,
brickster 0.2.15, and RTrino 0.1.0. Dependencies were installed in an isolated library.

| Check | Result |
| --- | --- |
| Package test suite | 1,029 passing assertions; no skipped scenarios |
| `R CMD check --no-manual` | No errors, warnings, or notes |
| Ten vignettes | Eight source guides, getting started, and sessions; built and rebuilt during the package check |
| Source guide apps | All eight construct with real OAuth clients and wait for sign-in |
| Rendered guides | All ten pages present; 20 local page links and anchors resolve |
| README apps | All eight construct; all ten outputs wait for sign-in |
| Playground apps | Client setup, queries, account replacement, and sign-out pass with mocked services |
| Documentation examples and local links | 46 R blocks parse; 89 local links resolve |
| BigQuery REST client | Bound parameters, result types, paging, refresh, and account separation |
| Redshift adapter | ODBC token and TLS options; connection reuse and cleanup |
| Trino DBI client | RTrino requests, paging, refresh, username changes, and sign-out |

Cloud responses are mocked. No live cloud queries or browser sign-ins ran
for this update. The tests cover connection cleanup, account and permission
changes, token refresh, and the example apps.

## Reproduce

Run from the repository root:

```sh
Rscript --vanilla tools/check-package.R path/to/check-library
Rscript --vanilla tools/check-docs.R
```

The extra library path is optional. The checker installs the package into a
temporary library and leaves the user's installed packages alone.

For real sign-in, platform permissions, and driver validation, use the
[integration checks](../tests/integration/README.md).
