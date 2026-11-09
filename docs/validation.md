# Validation record

## 9 November 2026: native ODBC error traces

ODBC adapters now call DBI with references to their argument values, keeping
bearer-token literals out of stored native error calls. Driver error classes
and messages are preserved. The shared call path is used by HANA, Snowflake,
Redshift, Azure SQL, Oracle and StarRocks.

The regression first failed six assertions on the previous implementation.
It now passes all 13 assertions with the real odbc 1.6.4.1 error boundary,
generated synthetic tokens and a nonexistent driver. It checks both textual
and serialized error objects for credential retention, and compares native
classes and messages with a direct DBI failure. The backend, HANA, Oracle,
Redshift, StarRocks and native option/ODBC contract suites pass together.
Air, Jarl and whitespace checks pass. No live cloud or native SAP/Oracle
connection was needed for this error-path regression.

## 9 November 2026: Azure PostgreSQL credential replacement

The helper now replaces its cached RPostgres connection on the next access
after the token changes. A focused regression first failed on the previous
implementation, then passed for default and named token targets. It checks
connection replacement, reuse, cleanup and absence of reactive query replay.
The PostgreSQL, backend and credential-recovery suites pass together.

`tools/check-azure-postgres.R` passes 12 assertions against PostgreSQL 18.3
with verified TLS, RPostgres 1.4.10 and libpq 16.10 on Windows/R 4.5.1. It
replaces the accepted password and synthetic authorization token, terminates
the original backend, and verifies successful reconnection without replaying
the completed reactive query. The disposable container is removed after the
check. This tests the real password transport and connection lifecycle;
Entra JWT validation and a live Azure server remain outside the fixture.

The focused source tests, documentation checks, Air and Jarl pass. The
documentation checker parses 87 R blocks and resolves 193 local links and
48 section anchors. The Azure PostgreSQL help page was regenerated.

## 8 November 2026: roxygen documentation review

Reviewed all 39 help topics in 26 R files. Descriptions now explain the
purpose and basic usage first, with source requirements and advanced
options in Details or named sections. Shortened protocol explanations
and replaced generated cross-platform related-function lists with the
existing source-specific links. Regenerated all 39 Rd files with roxygen2.

All 42 R files retain identical parsed implementation code, and every
existing help example parses identically. All help topics pass
`tools::checkRd()`. The website builds, with 1,596 local links and fragments
resolving across 69 rendered pages. The reference inventory still contains
all 38 exported functions and package help, grouped by source. Markdown
checks parse 87 R blocks and resolve 193 local links and 48 anchors.
Live database and browser sign-in tests were not rerun for these
documentation-only changes.

## 8 November 2026: guide and function-reference navigation

The guide menu now uses **All data source guides**, with **Databases and
related services** and **Cloud platforms** as its source categories.
PostgreSQL's article title is **PostgreSQL**. The reference groups related
functions by data source, with shared helpers listed separately.

With pkgdown 2.1.3, the full website builds successfully. Inventory checks
account for all 38 exported functions, package help and 22 guides without
duplicate entries. Rendered-page checks confirm each topic's group, the
PostgreSQL title and the navigation label. Documentation checks parse 87 R
blocks and resolve 193 local links and 48 section anchors.

## 8 November 2026: writing review of all vignettes

Reviewed and edited all 22 vignettes to explain purpose and basic concepts
before setup and advanced options. Removed 3,698 words, including repeated
demo settings, implementation details and test-suite descriptions. All 107
existing code blocks retain their contents.

The README and source-guide app tests pass with R 4.5.1 and shinyOAuth
0.7.0.9000 from the validation library. Documentation checks parse 87 R
blocks and resolve 193 local links and 48 section anchors. All 22 vignettes
render with html_vignette, and pkgdown builds the articles and function
reference. All 545 rendered local article links and fragments resolve.
Live Docker and cloud sign-in were not rerun for these prose and
organization changes.

## 8 November 2026: getting-started guide and article organization

Checked on Windows with R 4.5.1 and shinyOAuth 0.7.0.9000 from the repository's
validation library. The README and source-guide app tests pass. The new
getting-started app parses identically to the tested README and packaged
PostgreSQL example.

Documentation checks parse 87 R blocks and resolve 192 local links and 48
section anchors. The getting-started vignette renders with html_vignette;
pkgdown builds all 22 articles and the function reference. The article
inventory contains getting started and 21 data-source guides. Rendered
homepage links and redirects from the four retired article URLs resolve.
Help pages were regenerated with roxygen2. Live Docker and cloud sign-in
were not rerun for this documentation change.

## 8 November 2026: SAP HANA and HANA Cloud

Checked on Windows 11 with R 4.5.1, shinyOAuth 0.7.0.9000 and odbc 1.6.4.1.
`oauth_db_hana()` supplies the visitor's JWT access token through SAP HANA
ODBC with an empty username, JWT-only authentication and verified TLS.
Automatic native reconnect is disabled so reopening through the helper
obtains a current token.

The full source suite passes 6,194 assertions across 386 scenarios with
zero failures, errors, warnings or skips. HANA tests cover the real R ODBC
connection-string boundary, rejected credentials and native overrides,
independent visitor connections, named token targets, literal operation
scopes and lifecycle cleanup. SQLite DBI handles stand in for native SAP
connections in lifecycle tests. The complete HANA guide app constructs
and waits for sign-in. Documentation checks parse 100 R blocks and resolve
224 local links and 19 anchors. Air and Jarl checks pass for R and tests.

`R CMD check --no-manual` completes with zero errors, warnings or notes.
The installed-package tests pass, and vignettes build and rebuild successfully.

No SAP HANA driver, configured HANA database or live OAuth provider was
available. These checks establish R-side behavior; database principal
mapping, distinct visitor grants, expiry/reconnect and TLS compatibility
still need a configured deployment. See the
[HANA backend decision](hana-backend.md) for research sources and scope.

## 8 November 2026: generic Oracle OAuth and ORDS

The Oracle transport now accepts a JWT from the provider configured in the
database. Global-schema connections require `TOKEN_GLOBAL`. The explicit
`"end_user"` model verifies issuer, subject and audience in Oracle's
system-managed token context and rejects a missing or different context.
End-user connections reopen on access after token rotation, without
replaying completed reactive queries. Operation scopes are checked literally.

The separate ORDS HTTP client reads AutoREST pages and calls JSON handlers
using the visitor's token. It preserves native paging metadata, rejects
redirects and unsafe relative paths, retries only GET/HEAD after HTTP 401,
and discards responses after the selected authorization ends or changes.

The full source suite passes 5,731 assertions with zero failures, errors,
warnings or skipped scenarios. Documentation checks parse 92 R blocks and
resolve 210 local links and 18 anchors. Repository Air and Jarl checks pass.
`R CMD check --no-manual --no-tests` reports zero errors, warnings or notes;
package vignettes build and rebuild successfully. Tests were run separately
in the full source suite above.
Validation uses an isolated checkout containing only the Oracle changes,
while unrelated Supabase work continues in the main checkout.

Live Oracle/ORDS/provider integration remains unverified. The automated
checks exercise R's ODBC boundary, mocked immutable token context and HTTP
responses, and real SQLite connections for lifecycle behavior. See the
provider and version requirements in `docs/oracle-backend.md` before testing
a configured deployment.

## 8 November 2026: Supabase Data API and OAuth sign-in

Checked on Windows 11 with R 4.5.1 and shinyOAuth 0.7.0.9000.
The Data API helper reuses PostgREST and sends the project API key separately
from the visitor's current access token. Native sign-in uses Supabase's
OIDC discovery document; third-party providers can supply an authorization
without using the Supabase OAuth server.

| Check | Result |
| --- | --- |
| Full source regression suite | 5,750 passing assertions across 351 scenarios; zero failures, errors, warnings or skips in the isolated Supabase source |
| Focused Supabase, PostgREST and source-guide tests | Pass in the working checkout and in a clean source copy containing only the Supabase changes |
| API backend compatibility | Supabase and ORDS tests pass together in the combined checkout |
| Request authentication | Project keys remain separate from visitor bearer tokens across renewal, account changes and independent clients; ordinary PostgREST requests have no project key header |
| Authorization lifecycle | Queries wait for sign-in; late account-switched responses, permission loss and cross-session access are rejected |
| Key and endpoint validation | Reject secret/service-role keys, malformed legacy keys, insecure URLs and service URLs supplied in place of the project base |
| OAuth configuration | Mocked HTTPS discovery with the real shinyOAuth provider validates endpoints, PKCE, nonce and ID-token settings for public and confidential clients |
| Request behavior | Read-only refresh retry, no mutation replay, native RPC arguments and schema headers, exact JSON integers, and sanitized errors pass |
| Air and Jarl | Repository checks pass |
| Documentation | R examples parse, local links resolve, and the Supabase app constructs and waits for sign-in |
| Isolated `R CMD check --no-manual --no-tests` | Zero errors, warnings or notes; vignettes build and rebuild successfully |

No hosted Supabase account, native browser sign-in, or self-hosted gateway
was tested. Real refresh-token rotation, RLS enforcement for two users,
third-party JWT mappings and custom-domain configurations still need a
configured project. Research sources and setup requirements are recorded
in [the Supabase backend decision](supabase-backend.md).

## 8 November 2026: Oracle Database with Entra access tokens

Checked on Windows 11 with R 4.5.1. `oauth_db_oracle()` uses the Oracle
ODBC token-file interface, an inline TCPS descriptor, certificate matching,
and a `TOKEN_GLOBAL` authentication check before returning a DBI connection.

| Check | Result |
| --- | --- |
| Full source suite | 5,493 passing assertions; zero failures, errors, warnings or skipped scenarios |
| Oracle connection boundary | Real R odbc connection-string construction; per-connection token files and cleanup after connection errors and interruption |
| Oracle authorization lifecycle | Current token on reconnect; cleanup after account replacement, permission loss, sign-out and session termination |
| Authentication verification | Connections are closed when Oracle reports another method, returns an invalid response, or the verification query fails |
| Source guide | Complete Shiny app constructs, waits for sign-in and requests the database-specific Oracle resource and delegated scope |
| Air and Jarl | Repository-wide checks pass; two existing ADBC test style issues were corrected |
| Documentation | R examples parse and local links and anchors resolve; package vignettes build |
| `R CMD check --no-manual` | Zero errors, warnings or notes; installed-package tests and rebuilt vignettes pass |

No Oracle ODBC driver or Entra-enabled Oracle database was available.
These checks do not establish live database compatibility. Oracle client
and server versions, TLS trust, user mappings and per-user grants still
need validation against a configured Oracle deployment. Research sources
and the remaining live checks are recorded in `docs/oracle-backend.md`.

## 8 November 2026: runnable README and consistent example launches

The README starts its Docker services immediately after `library()` and
runs Shiny in the current R session. PostgreSQL is accessed through
PostgREST, so this example needs no native database driver. The packaged
script is `inst/examples/postgres/example.R`; run it with `source()`.
It registers service cleanup when Shiny starts and releases it on app stop.

Services-only mode uses loopback HTTP for R's OAuth requests and the
PostgREST demo endpoint. The HTTPS issuer and signed ID-token validation
are retained. The PostgREST HTTP exception accepts only the active demo's
exact address and is checked again before each request. Stopping the demo
revokes it, restores R options and removes Docker resources. System trust
stores and curl settings remain unchanged.

README and vignette apps use `runApp(..., launch.browser = FALSE)` with
the regular-browser comment after the call, following shinyOAuth. The
README's Learn more section points to both demo functions and setup guides.
Air formatted the R files and 84 fenced R blocks; a second pass made no changes.

| Check | Result |
| --- | --- |
| Focused demo, cloud and example suites | 855 assertions across 77 scenarios; zero failures, errors, warnings or skips |
| Formatted README, packaged script and database guides | 211 assertions across 22 scenarios pass after formatting |
| Real installed-package browser check, Windows | Alice and Bob sign in through Keycloak, see only their PostgreSQL rows, and sign-out clears the table |
| App stop | Docker containers are removed and R options restored before the child R process exits; cleanup does not rely on an exit finalizer |
| Services-only Compose configurations | All eight resolve; published ports bind to loopback, and port 18100 remains available to local R |
| Air and Jarl | Repository checks pass; fenced code formatting is idempotent |
| Documentation and website | 86 R blocks parse, 199 local links and 17 anchors resolve; pkgdown builds |
| `R CMD check --no-manual --no-tests` | Zero errors, warnings or notes; examples are exercised separately above |

No live cloud accounts were used. Logs are `.validation/services-*.log`;
real browser results are under `.validation/readme-demo/`.

## 7 November 2026: minimal app code in the README

The README now shows 36 lines of R: OAuth client setup, sign-in/sign-out,
a per-visitor PostgreSQL helper and one DBI query. The same example ships
in `inst/examples/postgres/app.R`, with instructions for using the packaged
Docker services. The runnable demos keep their styled layouts. All sixteen
database guides were reviewed; their complete apps already use simple
Shiny controls without CSS or layout panels.

| Check | Result |
| --- | --- |
| Documented-app tests | 156 assertions across 21 scenarios; zero failures, errors, warnings or skips |
| README/package consistency | Both parse to identical R expressions; the packaged file uses the repository's R formatting |
| Installed-package browser check | The minimal app passes real Keycloak sign-in and native PostgreSQL queries for Alice and Bob; each sees only their rows, and sign-out clears the table |
| Docker cleanup | Demo containers, network and database/TLS volumes are removed |
| Documentation in the committed snapshot | 86 R blocks parse; 202 local links and 17 section anchors resolve |
| Website | pkgdown builds; all README website targets, including the minimal-example anchor, exist |

The signed-out tests caught that calling `con()` directly as a DBI argument
wraps Shiny's wait-for-sign-in signal in a method dispatch error. The
examples retain `connection <- con()` before the DBI call. Logs for this
pass use `.validation/simple-examples-*.log`.
Browser results and service logs are under `.validation/minimal-readme/`.

Documentation was checked from an archive of `faeae61` to keep concurrent
workflow edits in the working tree out of the link check.

## 7 November 2026: simpler sign-in and clearer demo names

Demo credentials are now `alice` / `alice` and `bob` / `bob`. All four
Keycloak realm imports, app instructions, documentation and browser helpers
agree. Packaged apps show an explicit username/password table. Cloud app
titles and copied README headings no longer start with "Your".

The local launcher points to the sign-in details in the copied app, so an
older saved copy doesn't receive contradictory console instructions. It
also says when local Shiny is still starting. Cloud sign-in guidance now
reflects completed queries and a selected Databricks warehouse.

| Check | Result |
| --- | --- |
| Full source suite | 4,386 assertions across 297 scenarios; zero failures, errors, warnings or skips |
| Focused demo and cloud suites | Pass after the final changes |
| Credential audit | All four tracked realm imports use the matching username/password pairs; no old password format remains in tracked files |
| Fresh real-database browser checks | PostgreSQL in Docker, PostgREST in local R, OpenSearch in Docker and DuckDB Quack in local R pass Alice/Bob sign-in, expected data, sign-out, responsive layouts and cleanup; read-only checks also pass |
| Fresh cloud browser fixtures | Fabric and Databricks pass real local OAuth sign-in, explicit querying, result clearing and stopping; updated titles and status messages reviewed |
| Documentation and website | 85 R blocks parse; 202 links and 17 anchors resolve; pkgdown builds; the single README app matches the packaged PostgreSQL source |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes |

These six fresh browser checks supplement the earlier full 22-variant
layout pass. Cloud responses and connections are simulated; no cloud
accounts were used. Other host systems and remote Actions weren't run.
Current logs use `.validation/signin-*.log`; screenshots are under
`.validation/demos/` and `.validation/cloud-demo/`.

## 7 November 2026: bslib layouts and database-specific details

All sixteen demo apps now use bslib sidebars and cards. Sign-in controls
appear beside the query on desktop and above it on phones. Local apps show
their example SQL or API request, endpoint and table/index; cloud apps show
their configured target and relevant platform settings. Connection panels
explain how the database applies permissions without making extra queries.

The Docker images supply bslib 0.9.0 or later. Local-R and cloud launchers
check for that version before launching. Copied apps stay editable; a new
empty `path` obtains the refreshed templates without replacing existing edits.

| Check | Result |
| --- | --- |
| Full source suite | 4,386 assertions across 297 scenarios; zero failures, errors, warnings or skips |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes |
| Final focused suites | Pass, including rendered cloud connection values, credential omission, lifecycle guards and editable packaged apps |
| Docker/browser demos | All eight pass with the updated images, including data visibility, four write-rejection checks and stop-button cleanup |
| Local-R/browser demos | PostgREST, Trino, DuckDB Quack, libSQL, CrateDB and OpenSearch pass, including live app edits and forwarded endpoints |
| Cloud/browser fixtures | All eight pass real local OAuth sign-in, explicit querying, account-specific results, sign-out clearing and stopping |
| Responsive layout | All 22 browser variants pass at 390px: no horizontal page overflow, no clipped connection values, and sign-in controls above the results; desktop screenshots use 1440px |
| Documentation and website | Documentation checks and pkgdown build pass; README keeps one app matching the packaged PostgreSQL source |
| Compose and workflows | All eight standalone Compose contexts resolve; actionlint passes with bslib declared in browser jobs |

Visual review covers all sixteen apps. Phone previews caught and corrected
the initial sidebar order and clipped hostnames. Later focused/browser
checks cover final request-display and stylesheet refinements. Screenshot
and result artifacts are under `.validation/demos/` and
`.validation/cloud-demo/`; logs use `.validation/style-*.log`.

Local tests use real databases in Docker Desktop Linux containers on
Windows. Native PostgreSQL local R requires Linux, and the StarRocks
Windows ODBC driver isn't installed; both pass with Shiny in Docker.
Cloud responses and connections remain simulated, with real local Keycloak
sign-in. Live cloud providers, cloud drivers, other host systems and remote
Actions remain unverified.

## 7 November 2026: final review of local and cloud demos

Reviewed all eight Docker demos and eight cloud guides/apps for a clear
purpose, understandable setup and useful feedback. Local apps now explain
their data policy and show the demo accounts, certificate help and setup
guide. Cloud apps show their configured data source, explain the identity
query and guide users through sign-in, querying and editing the app.

Cloud drafts now survive restarting R. Back to setup opens a numbered
settings menu, keeping unrelated settings and app edits. Tests cover invalid
input, cancelling, returning later, changing the OAuth issuer and API scope,
and confirming a previously unfinished Redshift or ClickHouse integration.

| Check | Result |
| --- | --- |
| Full source suite | 4,345 assertions across 296 scenarios; zero failures, errors, warnings or skips |
| Focused setup regression checks | Pass, including persistent defaults for all eight platforms and integration-readiness recovery |
| `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes |
| Docker/browser demos | All eight pass Alice/Bob sign-in, expected data visibility, sign-out clearing and stop-button cleanup; the four write-check demos also confirm rejection |
| Local-R/browser demos | PostgREST, Trino, DuckDB Quack, libSQL, CrateDB and OpenSearch pass, including editing the copied app while it runs |
| Cloud/browser fixtures | All eight pass disabled querying before sign-in, explicit query execution, account-specific output, sign-out clearing and stop-button exit |
| Visual review | Captured browser screenshots for every app; reviewed purpose, instructions, data-source context, result explanation and layout |
| Documentation and website | 85 R blocks parse; 202 local links and 17 anchors resolve; pkgdown builds; README retains exactly one app matching the packaged PostgreSQL source |
| Compose and workflows | Eight standalone Docker configurations resolve; actionlint 1.7.12 passes |

Browser checks use Chrome and Docker Desktop Linux containers on Windows.
The local demos use their real databases. Native PostgreSQL local R requires
Linux; StarRocks local R wasn't run because its Windows ODBC driver isn't
installed. Both pass with their apps in Docker.

Cloud fixtures use real local Keycloak sign-in and native R, with simulated
cloud responses and connections. No cloud accounts or resources were used;
cloud identity providers, native cloud drivers and cloud-side authorization
remain unverified. Other host systems and remote Actions were not tested.
Artifacts are under `.validation/demos/`, `.validation/cloud-demo/`,
`.validation/review-*.log` and `.validation/package-check.json`.

## 7 November 2026: guides for all eight cloud platforms

`oauth_db_cloud_demo()` now includes Fabric, BigQuery, Snowflake, Azure SQL,
Azure PostgreSQL, Redshift and ClickHouse alongside Databricks. Each has
platform-specific console prompts, registration and permission guidance,
saved drafts and editable app files. Redshift and ClickHouse pause early
when their trusted-token integration isn't configured.

| Check | Result |
| --- | --- |
| Full source baseline | 4,240 assertions across 289 scenarios; zero failures, errors, warnings or skips |
| Final focused suites | All cloud-guide/app tests pass, including resource/scope correction, lazy named-target acquisition, account invalidation/restoration, query failure, result clearing and connection cleanup |
| Final `R CMD check --no-manual`, Windows / R 4.5.1 | Zero errors, warnings or notes; includes the final shared-UI changes |
| Installed-package browser fixtures | All eight platforms pass Alice/Bob login, no implicit SQL, explicit identity query, account-specific output, sign-out clearing and stop-button exit |
| Native-process credentials | Each browser fixture signs in using the platform-specific confidential-secret environment variable; no secret appears in generated app files |
| DBI lifecycle | Browser fixtures close their simulated SQL connections on sign-out; source tests also use real SQLite connections to check cleanup |
| Platform wiring | Real client constructors and configured SQL/API targets, Snowflake role, native driver/port/CA settings and BigQuery byte limit are checked without cloud calls |
| Documentation and website | 85 R blocks parse; 202 local links and 17 section anchors resolve; pkgdown builds and README website targets resolve |
| Workflow syntax | actionlint 1.7.12 passes; the browser workflow now has eight independent platform jobs |

Checks use Chrome, native R and Docker Desktop Linux containers on Windows.
OAuth sign-in is real against a local Keycloak instance. Cloud responses,
SQL connections and platform identity providers are substituted in browser
fixtures; native cloud drivers and cloud-side authorization remain unverified.
The apps are installed into temporary libraries and launched outside the
checkout, using paths with spaces. No cloud accounts or resources were used.
The final focused tests and package check follow the source baseline; they
include regressions added while checking interactive and browser behavior.

The guides document account/trial options without promising eligibility or
full-demo compatibility. Redshift's example uses Entra and IAM Identity
Center; ClickHouse uses Entra with its qualifying custom-JWT service.
Other identity-provider setups remain in the manual platform guides.
Other host systems and remote Actions were not tested. Browser results are
under `.validation/cloud-demo/<platform>/`; the final package report is
`.validation/cloud-platform-package-final.json`.

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
