# Validation record

## 7 November 2026: guided Databricks cloud demo

`oauth_db_cloud_demo("databricks")` now guides console setup with `cli`,
preserves an editable local app and supports public PKCE or confidential
OAuth registrations. Warehouse listing follows all result pages; a SQL
connection and identity query require an explicit button click.

| Check | Result |
| --- | --- |
| Full source suite | 3,989 assertions across 269 scenarios; zero failures, errors, warnings or skips |
| Final focused suites | Guide, generated app, warehouse discovery and existing API tests pass, including help, pause/resume, edit preservation, return to setup and scope loss/restoration |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes |
| Installed-package browser fixture | Real Keycloak login for Alice and Bob; warehouse selection, explicit query, account-specific output, sign-out connection cleanup and stop-button exit pass |
| Native R runner | A credential fingerprint confirms environment transport without recording the secret; generated files and process arguments contain no secret; return-to-setup exit status passes |
| Warehouse API | Mocked pagination, authorization loss, stale responses, cyclic page tokens, empty results and sanitized errors pass |
| Documentation and website | 84 R blocks parse; 187 local links and 17 section anchors resolve; pkgdown builds and README website targets resolve |
| Workflow syntax | actionlint 1.7.12 passes for the new cloud-demo browser workflow |

Browser checks use Chrome and Docker Desktop Linux containers on Windows,
launching the installed app outside the checkout with spaces in its path.
OAuth and the native R process are real; Databricks warehouse responses and
DBI operations are mocked. No Databricks account, registration or live SQL
request was used. Real-workspace registration and SQL-scope compatibility
remain unverified. Other host systems and remote Actions were not tested.
Final help-text and test additions have focused follow-up checks. Local
artifacts remain under `.validation/cloud-demo/` and `.validation/`.

Free Edition's lack of account-console and account-level API access blocks
the custom registration used here. The guide explains that limit before
asking for credentials. An eligible full-platform trial needs registration
access; its compatibility has not been established by these local tests.
See [Free Edition limits](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)
and [custom OAuth registration](https://docs.databricks.com/aws/en/integrations/enable-disable-oauth).

## 6 November 2026: editable demo apps in local R

`oauth_db_demo(app = "local")` runs the database and sign-in infrastructure
in Docker and an editable Shiny app in a separate host R process. Its
default remains `app = "docker"`. Local app files keep user edits and watch
for saved changes; certificate settings stay inside the app process.

| Check | Result |
| --- | --- |
| Full source suite | 3,909 assertions across 257 scenarios; zero failures, errors, warnings or skips |
| Final focused launcher and documentation tests | 265 assertions pass, including the process-isolation follow-up |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes after correcting an unqualified utility call |
| Local R browser demos | PostgREST, Trino, DuckDB Quack, libSQL, CrateDB and OpenSearch pass real Alice/Bob sign-in, expected data access, output clearing and stop-button cleanup |
| Local editing | Each local browser check loads a saved app edit before login and another saved edit between accounts; no Docker Shiny app container runs |
| Write restrictions | DuckDB, libSQL, CrateDB and OpenSearch reject writes from the local apps |
| Forced-exit cleanup | Force-ending the launcher also ends its local R app process |
| Existing Docker mode | PostgREST passes its two-account browser regression |
| Compose configurations | All eight local contexts resolve; browser/database ports bind to host loopback and port 18100 remains free for local Shiny |
| Documentation and website | 79 R blocks parse; 181 local links and 17 section anchors resolve; pkgdown builds and README website targets resolve |
| Workflow syntax | actionlint 1.7.12 passes; CI includes six local variants and eight Docker variants |

Checks use Docker Desktop Linux containers and Chrome on Windows. The
browser harness installs the current package into a temporary library and
launches it outside the checkout, with spaces in its configuration path.
The final process-isolation changes have additional focused, browser and
forced-exit checks. No cloud services or production credentials were used.

Native PostgreSQL local mode needs the matching Linux/libpq 18 client
build and was not run on this Windows host; its early diagnostic is tested.
StarRocks local mode needs an installed MySQL ODBC driver and plugin. An
extracted, unregistered Windows DLL was rejected by the ODBC manager, so
that local browser variant remains unverified here. Both databases retain
their existing Docker app mode. Other host systems and ARM were not tested.
Remote Actions have not run; local artifacts remain under `.validation/`.

## 6 November 2026: four more packaged Docker demos

`oauth_db_demo()` now also launches DuckDB Quack, libSQL, CrateDB and
OpenSearch with Keycloak browser sign-in. DuckDB, libSQL and CrateDB give
both accounts read-only access to a shared table; OpenSearch applies
per-user document permissions. Each app includes a rejected-write example.

| Check | Result |
| --- | --- |
| Full source suite | 3,847 assertions across 254 scenarios; zero failures, errors, warnings or skips |
| Final focused launcher and documentation-app tests | 190 assertions pass |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes |
| Four added installed-package demos | Real Keycloak browser sign-in for Alice and Bob, correct account and rows, database rejection of writes, blank output before login and after sign-out, and stop-button cleanup |
| Documentation checker | 77 R blocks parse; 180 local links and 16 section anchors resolve |
| pkgdown | Updated articles and function reference build successfully; all README website targets exist |
| Packaged configurations | All eight Compose contexts resolve their bind mounts; the README still has one app matching the packaged PostgreSQL app |
| Packaged demo workflow | Eight database jobs; actionlint 1.7.12 passes |

These checks use Docker Desktop Linux containers and Chrome on Windows.
The checker installs the current package and launches it outside the source
checkout, with spaces in its configuration path. The database versions are
DuckDB 1.5.4, libSQL 0.24.33, CrateDB 6.4.3 and OpenSearch 3.9.0.
The pinned DuckDB R client installs from a dated Posit Linux binary
repository; its image stage was built and exercised in the browser check.
ARM builds and other host systems were not tested. The original four demos
were not rerun for this follow-up; their results appear below.

The demos use Keycloak-issued tokens directly. libSQL uses Ed25519 tokens
with database permission claims and no audience. CrateDB uses a local
issuer/JWKS gateway. OpenSearch reads a signing-key snapshot during setup.
No cloud accounts or production credentials were used. Remote Actions and
website deployment still require a push; artifacts remain in `.validation/`.

## 6 November 2026: packaged demos and documentation website

The README now contains one PostgreSQL app. All database guides explain
connection values and sign-in setup, with shared OAuth and local demo guides.
The installed package supplies Docker contexts for PostgreSQL, PostgREST,
Trino and StarRocks through `oauth_db_demo()`.

| Check | Result |
| --- | --- |
| Full source suite | 3,838 assertions across 254 scenarios; zero failures, errors, warnings or skips |
| Final focused launcher and documentation-app tests | 182 assertions pass after the launcher follow-up |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes |
| Installed-package Docker demos | PostgreSQL, PostgREST, Trino and StarRocks pass real browser sign-in for Alice and Bob, separate row access, blank outputs before login and after sign-out, and stop-button cleanup |
| Documentation checker | 73 R blocks parse; 171 local links and 15 section anchors resolve |
| pkgdown | Website builds with all 20 articles and the function reference; every README website target exists in the output |
| README and Docker contexts | The single README app matches the packaged PostgreSQL app; all four Compose configurations resolve their bind mounts |
| New GitHub workflows | actionlint 1.7.12 passes |

The demo checks install the current package into a temporary library and
launch it outside the source checkout, using paths containing spaces.
Docker Desktop runs Linux containers on Windows; Chrome completes the real
Keycloak login. App containers install the pinned package API revisions in
`inst/docker/install.R`. No cloud services or production credentials are used.
Other host operating systems and ARM emulation were not tested locally.

The website builds into ignored `_site/`, preserving the contributor notes
in `docs/`. The new workflow can deploy after the commit is pushed and
GitHub Pages uses **GitHub Actions** as its publishing source. Remote
deployment has not run. Results remain under ignored `.validation/`.

## 4 November 2026: lifecycle and adapter follow-up

Added 291 assertions covering malformed authorization identities and methods,
session ownership, operation-specific permissions, denial recovery, unknown
expiry, ODBC option and port contracts, Trino configuration, and Databricks
provider settings. Production R code is unchanged in this follow-up.

| Check | Result |
| --- | --- |
| Full source suite | 2,595 assertions across 205 scenarios; zero failures, errors, warnings or skips |
| R 4.1.0 minimum core Docker suite | 1,293 assertions across 102 scenarios; zero failures, errors, warnings or skips |
| `R CMD check --no-manual` on Windows / R 4.5.1 | Zero errors, warnings or notes |
| R line coverage | 1,319 / 1,377 lines: 95.79% |
| Initial mutator samples | 30 Trino, 30 ODBC and 40 lifecycle edits; successful processes; zero timeouts |
| Selected mutation replays after the additions | 27 detected: 19 by assertions only, 2 by assertions and errors, 6 by errors only |
| Existing coverage investigated separately | 8 of those edits also detected by pre-existing tests outside the initial profiles |
| Final mutation-runner smoke checks | Strict 621-assertion lifecycle and 767-assertion ODBC baselines; sampled campaigns complete successfully with retained artifacts |
| Documentation checker | 63 R blocks parse; 142 local links resolve |
| Five-job mutation workflow syntax | actionlint 1.7.12 passes |

Most new scenarios exercise different inputs and state transitions on already
covered lines. The [mutation audit](mutation-testing.md) records which edits
the focused tests detect, distinguishes profile-selection gaps from missing
tests, and lists remaining investigations. The initial samples precede these
regressions and do not establish a current package-wide mutation score.

The lifecycle and ODBC profiles now include existing API/provider and adapter
tests alongside the new cases. CI samples 20 lifecycle edits, 40 ODBC edits,
and 60 each for transport, BigQuery and Trino, in independent weekly/manual
jobs with a 60-minute cap per job.

All checks ran locally. Platform requests and native Trino/ODBC connection
boundaries were mocked; SQLite connections and the minimum R Docker runtime
were real. Existing server/Keycloak fixtures were not rerun, and no cloud
resources were used. The new Actions configuration has not run remotely.
Machine-readable results remain under ignored `.validation/` directories.

## 4 November 2026: mutation-driven regressions

Checked on Windows 11 with R 4.5.1 and, for the minimum core configuration,
Docker Linux with R 4.1.0. Test additions cover authorization protocol errors,
native connection recovery, HTTP deadlines and request validation, minimum
SDK checks, and BigQuery job identities, redirects, retries and data types.

| Check | Result |
| --- | --- |
| Full source suite | 2,304 assertions across 194 scenarios; zero failures, errors, warnings or skips |
| R 4.1.0 minimum core suite | 1,115 assertions across 96 scenarios; zero failures, errors, warnings or skips |
| `R CMD check --no-manual` | Zero errors, warnings or notes |
| R line coverage | 1,318 / 1,377 lines: 95.72% |
| Validation harness self-tests | 15 assertions |
| Documentation checker | 63 R blocks parse; 141 local links resolve |
| Mutation workflow syntax | actionlint 1.7.12 passes |
| Mutator runner smoke check | Strict baseline passes; two sampled edits killed; complete artifacts; process exits successfully |
| Previously surviving edits replayed against new tests | 20 detected, with failures and execution errors distinguished |

The minimum lane uses exactly DBI 1.2.0, httr2 1.2.0, curl 6.4.0, Shiny 1.8.1
and testthat 3.2.0. Optional SDK version boundary tests simulate reported
versions; this run does not install each historical SDK release.

The [mutation audit](mutation-testing.md) records initial samples of 230
generated edits, timeout limitations, verified improvements and unclassified
survivors. These samples are not a package-wide mutation score. The committed
runner uses mutator 0.3.0, a fixed seed, isolated copies and no external
equivalence service. Three independent Actions jobs retain the reports.

These additions use SQLite and mocked service responses. Existing database
and Keycloak integration fixtures were not rerun for this test-only update.
No cloud resources were provisioned or queried, and the new Actions jobs
have not run remotely. Results are retained in ignored `.validation/`.

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
