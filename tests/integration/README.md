# Integration scenarios

Ordinary package checks run deterministic unit tests and Shiny smoke scenarios.
They do not contact cloud services or start interactive login. The offline
playground tests verify real local DBI reuse/disconnect, A-to-B replacement,
logout cleanup, separate Shiny sessions and bound-input validation.

## Local PostgreSQL and Keycloak

The [Docker Compose PostgreSQL/Keycloak fixture](../../integration/postgres-keycloak/README.md)
tests genuine browser OAuth, RPostgres token injection, server-enforced A/B row
policies, connection reuse, refresh, logout, wrong audiences and broken native
connections. It creates a disposable database rather than using your existing
server, and runs Chromium and R in containers. The narrow native helper belongs
only to this integration fixture; general native PostgreSQL support is not yet
a built-in adapter.

## Opt-in live transport check

`run-live.R` verifies the native adapter using two short-lived **delegated user**
tokens and an operator-defined fixture. It checks native connection reuse where
applicable, authorization replacement, A/B fixture expectations and logout state.
It does not exercise the browser OAuth exchange, refresh or consent. Its
test-only OAuthConnection constructor represents supplied fixture credentials;
production apps obtain references from a shinyOAuth module.

1. Install current shinyOAuthDB, shinyOAuth and the appropriate native client
   and driver. Configure the chosen backend using [the playground environment
   variables](../../playground/README.md).
2. Provision users A and B with distinct test grants or row-level security. Each
   should see only its expected fixture markers when running the **same query**.
   Do not add user filtering in the app to imitate platform policy.
3. Copy [fixture.example.R](fixture.example.R) to a trusted local file outside
   Git. Set `backend`, the read operation in `configure(spec)`, and a boolean
   `validate(user, value)` for your exact expected data. Do not embed secrets.
4. Supply short-lived tokens that the provider issued to A and B for this exact
   backend. Set these variables privately; the runner never prints them:

   | Variable | Meaning |
   |---|---|
   | `OAUTHDB_LIVE_A_TOKEN`, `OAUTHDB_LIVE_B_TOKEN` | Delegated access tokens, never app-only tokens |
   | `OAUTHDB_LIVE_A_EXPIRES_AT`, `OAUTHDB_LIVE_B_EXPIRES_AT` | Actual expiry as numeric Unix seconds, at least five minutes ahead |
   | `OAUTHDB_LIVE_A_SCOPES`, `OAUTHDB_LIVE_B_SCOPES` | Actual space-separated scope evidence for those tokens |
   | `OAUTHDB_LIVE_FIXTURE` | Path to your trusted fixture R file |
   | `OAUTHDB_LIVE_TESTS` | Must equal `true` explicitly |

5. From the repository root, run `Rscript tests/integration/run-live.R`. The
   runner prints a pass/fail summary without data, tokens, raw driver conditions
   or connection strings. A failure does not claim to diagnose the remote setup.

The fixture file is executed as trusted R application configuration. This is an
explicit test harness, not an API accepting uploaded/untrusted code. Fixed token
expiry/scope metadata is supplied by the operator; the remote database validates
the actual token and enforces grants. The harness does not validate JWT signatures
or fabricate a verified user identity.

## Real-browser acceptance checklist

Use the relevant playground with real shinyOAuth sign-in. Run two browsers or
separate browser profiles for A/B, plus A-to-B replacement in a single browser.
Record the tested package, native driver, database/platform versions and the
date. Cloud integration status stays experimental until the relevant scenarios
are observed against the deployment.

| Scenario | Expected observation |
|---|---|
| Fresh sign-in and consent | Only the configured delegated provider/registration and target are used; no CLI/PAT/application identity fallback |
| Missing initial target credential | The declared target is acquired through shinyOAuth; initial absence is not treated as denied consent |
| Same user, repeated native calls | Native SQL connection is reused within that session; parameter changes do not change query syntax |
| A/B data policy | Both users execute the same query and receive exactly their platform-authorized fixture rows |
| Concurrent browsers | A and B have separate handles/connections and never see each other's result or error |
| Replace A with B | A's displayed synchronous and task data clear; retained A providers fail; B obtains its own connection |
| Logout/session end | Results clear and cached native connections close; a saved old provider becomes unavailable |
| Token rotation | shinyOAuth refreshes the selected grant; ordinary token rotation does not requery data or change its authorization owner |
| Expiry before dispatch | Acquisition refreshes or reports an actionable authorization/lifetime error before submitting work |
| Revoked/missing API scopes | No result from the ended local permission epoch reappears after a later grant |
| Platform grant removal | New native requests receive the platform's denial or updated row policy; document the platform's established-session timing |
| Slow background request then logout/switch | Its late data **and error** are hidden; a replacement login never supplies its credentials |
| Latest queued reads | A newer pending read replaces the waiting read while the in-flight call finishes; write/unknown effects reject latest coalescing |
| Cancel | Local result publication stops; UI does not claim remote execution was stopped or a write undone |
| Token expiry during a worker operation | Worker fails locally with a safe error and cannot refresh or acquire a later login |
| Browser endpoint/credential override | Native task arguments cannot replace token, host, role, database, connection, alternate auth or source options |
| Untrusted HTTP destination/redirect | Upstream service policy blocks it before forwarding credentials |
| Error/redaction | UI, logs and task errors contain no access token, refresh token, connection string or raw response body |

Backend-specific checks remain necessary:

- **Azure SQL / on-premises SQL Server:** confirm explicit token injection, the
  actual database principal, group/RLS grants, encrypted transport and the
  deployment's native ODBC pooling behavior. Ordinary SQL Server auth should
  fail as unsupported.
- **Azure PostgreSQL:** confirm individual/group role mapping and membership,
  `verify-full` TLS, expired opening credentials and native reconnect/transaction
  behavior. A mapped group `current_user` is not necessarily a person's email.
- **Fabric SQL/KQL/DAX/GraphQL/OneLake:** verify each service's own token target,
  workspace/item/data grants, tenant switches, continuation/result URL policy
  and native result conversion. Do not assume one service's successful call
  proves another's permissions. Exercise fixed-token workers only where the
  upstream hook is available.
- **Databricks:** verify exact workspace binding, warehouse and Unity Catalog
  privileges, SQL parameters and expired/forced-refresh provider challenges.
- **Snowflake:** verify the configured OAuth integration's issuer, subject and
  role mapping; explicit supplied token precedence over ambient/token-file
  authentication; database/warehouse privileges and native-session lifetime.

Inspect remote audit records to corroborate the actual user principal and query
identity. A locally reported `ready` state is not evidence of remote access, and
closing a local connection does not establish immediate remote token revocation.
