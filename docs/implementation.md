# Implemented development contract

The package now implements the direction selected after the initial research: reuse native client APIs, reuse a connection per source handle and Shiny session, and offer optional direct-function background tasks. The historical API draft includes callback-based task proposals that were superseded.

## Ownership and authorization

`oauth_db_session(source, authorization)` requires an open owning Shiny reactive domain. Its authorization input accepts a pinned object, a Shiny reactive, or a no-argument accessor returning a connection or `NULL`. The native route is the modern `OAuthConnection` from `oauth_module_server()` or `oauth_connections_server()` and their public `connection()` factories. The class is unrestricted: other provider objects use the same method contract directly or through `oauth_db_authorization()`. The bridge does not manage browser login, refresh credentials, OAuth storage or consent itself.

The contract is a non-secret stable authorization `id`, `access_token(required_scopes, min_valid_for, force_refresh, async, target)`, and `has_scopes(scopes, target)`. Scope evidence must be one logical value, reactive, and false when the pinned grant ends; it is independent of cached token expiry. Optional `targets()` exposes a named target's `not_acquired` state. Single-resource callbacks may omit `target` only when the source selects `NULL`; named target routing cannot be dropped. Custom callbacks must honor lifetime, scope, asynchronous and refresh requirements and stay pinned to this user grant, without acquiring another login or ambient host credentials.

Keep the connection object stable through token rotation and create a fresh object/ID for replacement authorizations, even for the same user. A replaced reference also advances the local generation if its ID was reused, so captured providers cannot silently follow the new object. A retained manager ID alone does not prove liveness: the owning session, pinned reference and reactive permission evidence are also checked. The legacy shinyOAuth `oauth_connection()` wrapper does not establish these modern pinning/acquisition semantics.

App login and database consent are separate selections. A database handle reads only its supplied authorization accessor; it never looks up an app login, a sole other provider or a default manager grant as a fallback. Use `manager$connection(explicit_id)` when multiple grants exist; ambiguous manager access reports `selection_required`, closes the old transport, and prevents operation submission. A single manager can retain both login and database client profiles, or the app's persistent first-party login can live beside a database manager. Browser retention binds a browser; account retention requires shinyOAuth's trusted local app-session owner resolver, not an email or database token claim. Full callback navigation ends an ordinary single-module Shiny login session, so composition must account for that lifecycle.

Every source handle has an authorization generation. Replacement or logout, session end, and observed loss of watched local scopes advance it and close the cached native connection. Normal token rotation preserves it. Additional scopes used by an operation are watched too. An unacquired declared target is allowed to acquire its first token through shinyOAuth; absence alone is not denied consent.

`$generation(required_scopes = ...)` is a reactive scalar for invalidating application-owned data/error caches. `$status()` is diagnostic metadata without tokens. Neither reports remote database grant changes: the remote service enforces them on its own timeline, including established-session behavior. The package cannot intercept every arbitrary native call or app cache.

Native connections are reused within a handle while valid and while the acquired token remains unchanged. A changed opening token causes a new native connection on the next access. Databricks/Fabric request providers obtain current credentials from the same captured authorization. Saved providers never switch to a later login. There is no connection sharing across users or sessions and no automatic transaction replay. Driver-manager pooling and native reconnect behavior remain deployment/client concerns.

## Native APIs and tasks

`$connection()` returns native DBI. `$token_provider()` returns the relevant package's provider or callback. `oauth_db_with_connection()` and `oauth_db_with_client()` check synchronous values and errors against the captured authorization before return, and reject live/lazy results. `oauth_db_query()` is a small DBI convenience. Synchronous native query conditions retain their native behavior; apps should present safe errors without logging sensitive driver conditions. Connection-opening errors and worker errors are sanitized.

`oauth_db_task(db, exported_function, ...)` maps supported DBI, brickster and fabricQueryR functions. It does not serialize a user callback. Explicit operation bindings protect source endpoints, database/role settings, credential arguments and alternate authentication paths. Native `DBI::Id` and `DBI::SQL` argument values remain supported. The initial mapping is intentionally finite; raw native APIs provide the full client surface synchronously.

Tasks use Shiny ExtendedTask plus either mirai or future, without changing the app's global worker configuration. They maintain serial/latest/ignore queues, correlate each outcome with its invocation, and check the captured authorization before exposing either value or error. Coalescing waiting work requires an explicit read effect. Cancellation invalidates local publication only.

The owning process calls the selected authorization's `access_token(async = TRUE, ...)`. Worker payloads contain one short-lived access token, source configuration, operation mapping, arguments and non-secret capture identifiers. Token attributes from custom SDKs are stripped before transport or worker delivery; only the bearer string is retained. Plain-data validation rejects environments, callbacks, live connections and other credential-bearing runtime objects. Workers cannot refresh or acquire a subsequent login. Native provider objects are recreated in the worker through public upstream hooks.

The deadline starts before acquisition and uses the requested minimum credential lifetime conservatively. Delays consume that budget. Remote executor hosts need synchronized clocks. Token access and outcome publication after the deadline fail locally; this is not a statement timeout or remote cancellation. A remote revocation may reject an otherwise locally valid token earlier. Raw worker errors, warnings and messages are not exposed.

## Upstream changes

fabricQueryR gained one public hook, `fabric_token_provider()`, adapting an explicit user credential callback while reusing its existing audience routing and endpoint policy. The bridge does not copy the package's private policy attributes or use `:::` to obtain credentials. Existing `fabric_shiny_token_provider()` remains available upstream. No native query engines were moved into this repository.

Databricks reuses the fork's existing `db_token_provider()`, `db_oauth_provider()`, `DatabricksSQL()` and REST functions. Azure SQL uses odbc's existing `attributes = list(azure_token = ...)` interface. PostgreSQL uses RPostgres's password argument and verified TLS. Snowflake uses explicit ODBC OAuth authentication, token and role with no token-file argument. Each platform still requires its own user provisioning, app registration, network access and authorization policy.

## Validation scope

Deterministic tests use synthetic references only as test fixtures, native SQLite for connection behavior, mocked native driver calls for exact token injection, and actual mirai/future processes for worker execution. Custom-object tests cover all input forms, permission evidence, target routing, independent grant selection and stale async acquisition. Multiple-connection scenarios verify separate login/database grants and manager selection. They verify bridge behavior rather than simulate proof of cloud data policy.

The playground contains a local fixture app and configured live examples. Opt-in integration tests require short-lived delegated A/B tokens and an operator-supplied query with exact expected authorized rows. They exercise transport and replacement, not browser exchange or refresh. The separate real-browser checklist covers those flows, provider challenges, RLS, endpoint policy and remote audit identity.

Cloud adapters remain experimental until these live deployment-specific checks pass. Native PostgreSQL 18 OAuth, Google/AWS federation, automatic schema discovery and full client operation registries remain future work; they are not silently emulated with application credentials.
