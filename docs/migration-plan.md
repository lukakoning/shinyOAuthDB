# Migration and implementation plan

Historical migration proposal. The first implementation and a public Fabric credential hook are now present; [implementation.md](implementation.md) records what was implemented and what remains experimental. The original proposal below is retained as research history.

Status: proposed work, reviewed 2 October 2026. This draft changes no sibling package and includes no production implementation. The user confirmed a research/architecture/API deliverable, shared Shiny query/task lifecycle, and delegated user access only.

## 1. Move integration ownership without copying engines

| Existing code | Proposed action | Must remain upstream |
|---|---|---|
| Fabric `fabric_shiny_config()`, UI/server wiring | Adapt presets and replace duplicated lifecycle with shinyOAuthDB handles | Fabric operation/resource semantics |
| Fabric `fabric_shiny_token_provider()` | Use exported function initially; move capture of OAuthConnection after public generic policy seam exists | Audience-aware `token` support and endpoint-policy enforcement |
| Fabric example query/task coordination | Reuse its service examples and parameterization; replace stale-outcome handling with shared tasks | SQL/DAX/KQL/GraphQL/OneLake engines and result conversion |
| brickster `db_shiny_config/ui/server` | Adapt Databricks preset; use shared source/session lifecycle | Generic workspace discovery/provider facilities where independently useful |
| brickster `db_shiny_task()` | Use result/error generation envelope as an implementation reference for the shared task | Statement execution/poll/fetch/cancel and DBI/dbplyr machinery |
| brickster `db_token_provider()` | Call this public, Shiny-independent hook | Host binding and per-request bearer authentication |

The [local research](research-local-migration.md) records exact functions, source lines, exports, tests, licenses, and current migration constraints. Do not copy private credential structures or call `:::` from the new package.

Initially preserve old integration entry points in each package. Publish migration examples using shinyOAuthDB; deprecate wrappers only when replacements preserve the intended behavior. Optional forwarding wrappers can use `requireNamespace("shinyOAuthDB")`, avoiding hard dependency cycles. Existing upstream maintainers may prefer deprecation plus documentation rather than forwarding dependencies; either route can retain the generic token hooks.

## 2. Dependency boundaries and provenance

Proposed core imports: `shinyOAuth`, `shiny`, `DBI`, `R6`, `rlang`, with additional small dependencies only when the implementation actually uses them. Use `shiny >= 1.8.1` if ExtendedTask is part of the public task implementation. `promises`, `mirai`, and `future` can initially be optional task dependencies, with one explicit configured executor and a clear error when missing. Never configure/replace the application's global worker plan from a query helper.

Suggested optional clients: `fabricQueryR`, `brickster`, `odbc`, `RPostgres`, `dbplyr`, and any result-format packages actually needed by chosen paths. Plain Azure SQL should not require Fabric. PostgreSQL should not require ODBC. Native Microsoft/Snowflake ODBC drivers and an ODBC manager remain deployment dependencies; an R install does not install every native driver.

Verified feature floor: `odbc >= 1.3.4` introduced supplied Azure SQL token attributes. Choose a higher floor only for additional required APIs or tested fixes. Microsoft ODBC Driver 18 is the proposed initial supported baseline, not the first historical version to support tokens. Azure PostgreSQL's exact historical RPostgres floor remains unestablished; validate the selected release and libpq build. Fabric ADBC remains optional and retains the existing external mssql driver checks. [SQL/PostgreSQL research](research-sql-postgres.md)

The inspected shinyOAuth development version is `0.6.1.9000`; the required access-token and target APIs must be in a real released dependency before a normal release. The brickster callback support is inspected in the user's fork, not assumed present in the upstream CRAN package. Development installation guidance should pin the relevant commit/version and identify repository ownership; a support matrix should name the tested versions.

Fabric source is MIT. brickster is Apache 2.0 and carries license/NOTICE material. Calling public APIs is preferable to transplanting implementation. If code is copied/adapted, preserve provenance, copyright/license notices, any required NOTICE content, and modification information; do not assume a new MIT header replaces those obligations. Choose final package licensing once copied code, if any, is identified.

## 3. Phased delivery

### Phase A — shared core and existing-connection adapters

Build validated source descriptors, one-session handles, public OAuthConnection acquisition, explicit target routing, native scoped operations, and redacted conditions. Implement connection/permission/source epochs and guarded outcome envelopes before async convenience. Start with Fabric synchronous existing-connection integration and brickster callback integration.

The broker must work with both `oauth_module_server()` and `oauth_connections_server()`. Support optional/unacquired token targets: the first operation can acquire them; readiness checks must not treat absence of a cached token as denial. Preserve ordinary-refresh stability and never reuse a retired outcome after observed permission loss/regrant.

### Phase B — shared tasks and policy-preserving Fabric worker seam

Implement ExtendedTask wrapper, main-process async credential acquisition, explicit operation descriptors, worker-local connection creation, outcome guards, queue policy, and cleanup. Use brickster's error-and-value envelope as a reference, while avoiding its current implicit custom-function environment rewrite and making executor/queue behavior explicit.

**Fabric release gate:** add a documented public, Shiny-independent constructor/materializer for an audience-bound external credential with endpoint policy. The existing exported `fabric_shiny_token_provider()` is sufficient for a live synchronous adapter, but not a clean fixed-token worker that cannot retain an OAuthConnection. Do not copy `fabric_endpoint_policy` attribute structures or internal profile lists as a substitute. Existing upstream transports continue to enforce the same policy after refactoring.

**Deadline release gate:** distinguish dispatch, request, and whole-operation enforcement. brickster currently checks bearer requests through providers, but signed result downloads and polling do not necessarily have a single total timeout; `fetch_timeout` is per chunk. Add public upstream timeout/continuation hooks where stronger claims are required. Conservative token-use deadlines and guarded publication are useful without claiming remote query cancellation or universal wall-clock enforcement.

### Phase C — general SQL adapters

Implement Azure SQL directly with `DBI` + `odbc` token attributes; share driver/endpoint/auth option validation with the SQL Server transport where practical. Reuse `fabric_sql_connect()` for Fabric instead of copying its engine. Support Entra-enabled on-premises SQL Server through the same transport with distinct documented provisioning checks.

Implement Azure PostgreSQL Flexible Server with `RPostgres`, a token password, an approved database-role mapping, and verified TLS. Treat user and group-role behavior explicitly. Assess native reconnect/reset behavior before enabling session reuse **or managed transaction guarantees**, including per-operation scopes: native result creation can reconnect independently of the bridge.

Disable or establish absence of native ODBC pooling for initial support, or prove identity partitioning and revalidation. Per-operation `dbConnect()`/`dbDisconnect()` alone does not prove a new physical connection or fresh authentication. Native pooling is separate from R `pool`; do not invent a connection-string flag for a process-level ODBC manager setting.

### Phase D — Snowflake and migration rollout

Implement a thin ODBC OAuth adapter with explicit account, role, warehouse, and credential injection. Prefer a complete explicit `odbc::odbc()` configuration or a verified helper path. Prove that neither helper discovery, credential files, DSN values, nor `TOKEN_FILE_PATH` can replace the selected user token. Test External OAuth role restrictions and Snowflake OAuth separately.

Publish one runnable multi-source Shiny example and standalone existing-login examples. Deprecate duplicated platform Shiny helpers gradually once common replacements and target/identity behavior are proven. Keep platform-specific functions and public callback hooks available without shinyOAuthDB.

### Phase E — gated extensions

| Track | Prerequisite before an adapter claim |
|---|---|
| PostgreSQL 18 native OAuth | Configured server validator + public per-connection R/libpq bearer hook; do not pass the token as an ordinary password for native OAUTHBEARER |
| BigQuery | Upstream per-request/per-connection user credentials, a verified isolated process mode, or a tested token-capable driver; no temporary switching of global `bq_auth()` |
| Google Workforce federation | Correct subject-token kind/export, STS audience and mappings, direct user principal permissions, compatible isolated R client |
| Databricks federation | Correct account/workspace policy and explicit subject-token exchange/export; direct native/Entra token route remains separate |
| Redshift / Athena | Vendor native Entra or Identity Center TIP setup and exact driver fields; prove human identity/policy preservation, result access, credential-cache isolation |
| ADBC / Arrow / large streams | Current supported R/native releases, lifetime ownership, explicit IPC for process transfer, preserved numerical types |
| Per-user connection pools / worker affinity | Measurements show a need; verified ownership partitions, session state cleanup, expiry/reconnect, bounded resource consumption |

No plain STS role/service-principal/password fallback is added to make an unsupported backend appear supported.

## 4. Testing that establishes the intended guarantee

### Meaningful offline tests

Use fake authorization references and platform transports to test the common lifecycle. Do not mirror every constructor implementation with trivial tests.

- Two concurrent Shiny sessions cannot use each other's references, connections, callbacks, task outcomes, or selected authorization IDs.
- Ordinary token rotation preserves the data/query generation; replacement login, source/role selection changes, and observed permission loss permanently retire old outcomes.
- Initial unacquired target -> acquisition works; a denied optional target does not erase unrelated source access.
- Recheck after delayed credential acquisition, before worker dispatch, and before success/error publication. A queued operation cannot silently switch to a newer login.
- Both a stale successful value and a stale error are discarded. Include pending, completed, cancelled, and late-result cases; protect downloads/progress too.
- No worker payload contains a session, OAuthConnection, refresh credential, client secret, live DBI/Arrow pointer, or retained provider closure. Reject unsupported custom worker dependencies explicitly.
- Reject credential/endpoint/TLS/DSN overrides and cross-resource token routing. Explicit callback failure never selects ambient credentials.
- Normal/finally cleanup runs for connection-open failure and query error; cursors/results close correctly. Busy invalidation, cancellation, session end, or worker termination request cleanup/cancellation best effort, since the parent cannot instantly close another process's native handle.
- No automatic statement replay after an ambiguous timeout or lost connection. Audit the chosen upstream retry behavior.
- Error printing/logging does not reveal tokens, passwords, connection strings, response bodies, query parameter values, or captured worker environments.

Port/adapt the relevant existing Fabric Shiny token/config/async tests and brickster provider/Shiny-task tests as described in the local report. Keep platform-engine tests in their owning packages.

### Live acceptance tests per supported adapter

Run two actual users with different permissions in the same R/Shiny process and prove:

1. The server/platform accepts the intended principal and configured role; use backend-specific identity/audit evidence rather than assuming `current_user` is an email.
2. A permitted query returns only expected data, and a forbidden table/row/operation fails according to the platform policy. Verify the relevant row/column/model/storage policies for the **actual access route**.
3. Deliberately wrong audience/issuer/tenant/role tokens are rejected, with no alternate credential source selected.
4. Expiry, acquisition, reconnect, group membership, source switching, and logout behave as documented. Observe established-session revocation latency instead of asserting immediate revocation.
5. Native pooling and any driver credential/result caches are absent or partitioned; Windows/Linux deployment and CA settings work as supported.
6. A worker invocation cannot publish data/errors after local invalidation; request/operation deadlines and cancellation match their declared capability level.
7. Protected data types retain precision and documented NA/timezone/decimal semantics through the reused native clients.

Test these against a named driver/package/server version matrix. No live acceptance test was run for this research draft.

## 5. Proposed package tree after implementation starts

```text
DESCRIPTION / NAMESPACE / LICENSE material
R/
  source.R                  # static descriptors and validation
  requirements.R            # auth plans and operation requirements
  session.R                 # owner, selection, epochs and cleanup
  credentials.R             # public acquisition and worker material
  connection.R              # scoped native connection leases
  query.R                   # thin DBI/native query dispatch
  task.R                    # guarded nonblocking lifecycle
  conditions.R              # stable redacted errors/events
  adapter-sql-server.R
  adapter-postgres-azure.R
  adapter-fabric.R
  adapter-databricks.R
  adapter-snowflake.R
tests/testthat/              # lifecycle, adapters and credential isolation
inst/examples/              # existing login; multi-source; async; migration
vignettes/                  # setup, delegated identity, tasks, adapter authoring
```

Keep query engines out of this tree. Start with concrete adapters and extract shared helpers when two transports need them; avoid designing an abstraction for every hypothetical database before the first two migrations work.

## 6. Release checklist and unresolved owner choices

The confirmed design choices need no further approval in this draft. Remaining routine recommendations are: per-operation physical handles first, driver-based SQL support alongside REST engines, optional Snowflake after its auth-precedence tests, reads first with native scoped transactions where supported, and complex federation/BigQuery later.

Before implementation, settle the publish destination/license, whether the brickster hooks will be upstreamed or supplied through the fork, and the preferred first live environments/users. Those do not change the shared architecture. Do not describe a backend as supported until its public hooks, dependency availability, endpoint policy, identity isolation, and live permission behavior meet the gates above.
