# Local integration and migration research

Research date: 2026-10-02. This report describes the checked-out sources, not a claim that these features are available in released CRAN packages or the official upstream brickster repository. No sibling repository was modified, and no live database tests were run.

The agreed scope is a design/research/API draft, a shared query/task lifecycle, and delegated user identity. Automatic application-identity fallback is outside that scope.

## Inspected source snapshots

| Repository | Local snapshot | Declared package version | Remotes and ownership evidence |
| --- | --- | --- | --- |
| `../fabricQueryR` | `3439e2052b82d8ac41141d8e397763fd6a6c7d96` | `1.0.1.9000` | `origin` is `KennispuntTwente/fabricQueryR`; `DESCRIPTION:4-11` names Luka Koning and Kennispunt Twente. |
| `../brickster` | `95b0065f393de7658d98ecd187f5b1dabc2e8c5f` | `0.2.14` | `origin` is `lukakoning/brickster`; `upstream` is `databrickslabs/brickster`; `DESCRIPTION:4-8` names upstream authors and Databricks. |

Both working trees were clean at inspection. `../brickster/AGENTS.md` was read. Its conventions favor thin API wrappers, public callback hooks, stable returns, domain-specific implementation staying in brickster, and migration guidance for deprecations. No `AGENTS.md` was found beneath `../fabricQueryR`.

Source references below use paths relative to the shinyOAuthDB repository root, followed by line numbers. They refer to the snapshots above.

## Main architectural finding

Both packages already have the essential seam for a bridge package: their existing data APIs accept externally managed credentials. shinyOAuthDB can own Shiny session integration, service declarations, adapters, query dispatch, and result lifetime checks while continuing to call the public data APIs. Reimplementing SQL engines, Fabric item classes, Databricks REST endpoints, Arrow conversion, or dbplyr translation would duplicate substantial tested behavior.

The reusable boundary is a **live session-bound token provider in the main Shiny process** and a **fixed access-token snapshot plus ordinary operation arguments in a worker**. These are different objects with different lifetimes. They must not be represented as an interchangeable globally cached token string.

## Fabric: what already exists

### Configuration and resource declarations

`fabric_shiny_config()` creates a shinyOAuth client for a fixed Entra tenant, with validated ID tokens, PKCE/nonce behavior from the provider, disabled Graph UserInfo requirements, `openid`, `profile`, and `offline_access`, and explicitly declared token targets. Its supported services are Fabric discovery, SQL, DAX, KQL, OneLake, and GraphQL. The implementation requires a client secret and currently excludes `.default` consent and incremental consent. These restrictions belong to the present convenience configuration; they are not proof that every other backend must impose them. Sources: `../fabricQueryR/R/fabric_shiny_config.R:8-39`, `:53-114`, `:126-143`.

The resource catalog contains:

| Service | Token resource | Target name | Default delegated permission(s) | Source |
| --- | --- | --- | --- | --- |
| Fabric discovery | `https://api.fabric.microsoft.com` | `fabric` | `Workspace.Read.All`, `Item.Read.All` | `fabric_shiny_config.R:173-179` |
| SQL | `https://database.windows.net/` | `sql` | `user_impersonation` | `fabric_shiny_config.R:180-186` |
| DAX | `https://analysis.windows.net/powerbi/api` | `power_bi` | `Dataset.Read.All` | `fabric_shiny_config.R:187-193` |
| KQL | `https://api.kusto.windows.net` | `kusto` | `user_impersonation` | `fabric_shiny_config.R:194-200` |
| OneLake | `https://storage.azure.com` | `storage` | `user_impersonation` | `fabric_shiny_config.R:201-207` |
| GraphQL | `https://analysis.windows.net/powerbi/api` | `power_bi` | `GraphQLApi.Execute.All` | `fabric_shiny_config.R:208-214` |

Paths in this table are under `../fabricQueryR/R/`.

DAX and GraphQL intentionally share one token target with unioned scopes while retaining separate endpoint policies (`fabric_shiny_config.R:85-91`). This proves that the unified design needs three separate concepts: a data source, an OAuth token target, and an allowed destination policy. A one-to-one `database == audience == service` assumption will fail for these integrations.

### Adapting an existing login

The exported `fabric_shiny_token_provider(connection, services, scopes, targets, endpoint_hosts, min_valid_for)` already accepts an existing module-managed shinyOAuth `OAuthConnection`. It does not add another login module. The callback has the public transport shape `function(audience, force_refresh = FALSE)` and forwards target, scopes, minimum validity, and forced refresh to `connection$access_token(async = FALSE)`. It captures the original connection. Sources: `../fabricQueryR/R/fabric_shiny_token_provider.R:1-34`, `:37-94`.

Its routing is deliberately exact: it recognizes known package audience aliases or a scope bundle that is wholly contained in a declared service profile. It does not interpret an arbitrary resource prefix as authorization for another operation (`:96-115`). The existing internal `.fabric_audience$sql` alias is literally `https://database.windows.net//.default`; this is a package callback routing key, not the delegated SQL scope to pass to shinyOAuth (`../fabricQueryR/R/auth.R:1-20`, `fabric_shiny_config.R:180-185`, `:255-288`). Preserve the adapter's exact alias handling instead of inventing string normalization.

The provider carries an attribute named `fabric_endpoint_policy`. Credential adaptation, secondary service use, HTTP calls, SQL calls, SQL retries, and Delta reads preserve/enforce it. It checks HTTPS, no URL credentials, permitted port, built-in hostname suffixes, and explicitly configured extra hostnames. Sources: `fabric_shiny_token_provider.R:91-92`, `:117-140`; `../fabricQueryR/R/auth.R:97-125`, `:268-298`, `:608-619`; `../fabricQueryR/R/fabric_sql_connect.R:353-384`, `:757-760`.

### The generic Fabric credential seam

Most public Fabric functions accept `token`, which may be an AzureAuth token object, fixed bearer string, or provider function. Internally, `fabric_credential()` adapts all forms into one audience-aware interface. Supplying an explicit token bypasses automatic AzureAuth acquisition; `auth_args` cannot be combined with supplied credentials. Callback failures propagate rather than selecting a different credential source. Sources: `../fabricQueryR/R/auth.R:54-139`, `:558-619`.

This ordinary external-provider support should stay in fabricQueryR. A bridge that only supplies tokens must never change platform authentication silently to application credentials, environment credentials, AzureAuth interactive login, or another user's credentials.

Endpoint policy presently depends on functions named `fabric_shiny_*` inside fabricQueryR. That creates a migration constraint: **moving those files wholesale would break the remaining ordinary transports**. Before removing Shiny dependencies upstream, extract generic credential-policy validation and resource routing into Shiny-independent internal helpers or a documented public hook. Until that exists, the new adapter can call the existing exported `fabric_shiny_token_provider()` as a compatibility step, accepting that this temporarily retains Shiny adapter code in fabricQueryR.

### Session convenience API

`fabric_shiny_ui()` delegates callback routing to `shinyOAuth::oauth_ui()`. `fabric_shiny_server()` returns session-local `ready`, `status`, `identity`, `generation`, `token_provider`, `access_token`, discovery/request helpers, `prepare`, and explicit login/logout/reauthorization methods. It uses an eight-hour finite authorization age and leaves refresh/token management to shinyOAuth. Sources: `../fabricQueryR/R/fabric_shiny.R:13-16`, `:82-116`, `:126-345`.

`ready(service)` means recorded scope coverage, not proof of database access or freshness. `status()` distinguishes target state from acquisition error. Generation is connection identity and stays stable over routine refresh. `prepare()` acquires configured targets independently, allowing Fabric access to survive an optional target failure. These useful semantics should migrate, with domain-neutral naming and per-source status (`fabric_shiny.R:31-79`, `:205-247`, `:259-290`).

Current code starts the OAuth module with `async = FALSE` and `prepare()` synchronously loops over every service at new authorization (`:106-114`, `:220-246`). The unified design should decide explicitly whether to keep this behavior or replace it with asynchronous targeted acquisition. A generic Shiny bridge should avoid accidentally blocking all visitors during multi-resource prefetch.

### Existing query and connection engines to reuse

Fabric already implements public engines for SQL, DAX, KQL, OneLake/Delta, and GraphQL, plus discovery and authenticated R6 item classes. Examples of public entry points: `fabric_workspaces()` (`../fabricQueryR/R/fabric_discovery.R:62`), `fabric_item()` (`:444`), `fabric_sql_connect()` (`../fabricQueryR/R/fabric_sql_connect.R:286`), `fabric_sql_query()` (`:596`), `fabric_pbi_dax_query()` (`../fabricQueryR/R/fabric_pbi_dax_query.R:163`), `fabric_kql_query()` (`../fabricQueryR/R/fabric_kql_query.R:550`), and `fabric_graphql_query()` (`../fabricQueryR/R/fabric_graphql_query.R:223`).

`fabric_sql_connect()` already builds ODBC or ADBC connections through DBI. ODBC receives `attributes = list(azure_token = token_value)` and rejects conflicting authentication, endpoint, TLS, and token attributes. ADBC builds a token-bearing SQL Server URI and validates the external driver version. Sources: `fabric_sql_connect.R:397-485`, `:1231-1257`, `:1530-1676`, `:1983-1998`.

`fabric_sql_query()` is a one-shot SELECT/WITH...SELECT helper, supports bound parameters and tibble/Arrow stream results, keeps retry policy sensitive to caller-declared idempotency, and closes each non-stream connection in a finally block. Its Arrow stream owns the result/connection until release. Sources: `fabric_sql_connect.R:511-565`, `:636-649`, `:739-827`, `:2148-2170`. Numeric precision policy, integer64 placeholder rewriting, SQL parsing, and result conversion are substantial platform-engine behavior and should remain in fabricQueryR.

General Azure SQL can reuse the same ODBC access-token transport pattern. That does not mean shinyOAuthDB should depend on Fabric parsing/SQL read restrictions to connect ordinary SQL Server. A thin Azure SQL adapter over `DBI` + `odbc` is a better boundary than treating all SQL Server installations as Fabric items. Existing generalizable validation can be extracted into a shared component only when there is a concrete need and clear ownership.

## Databricks: what already exists

### Provider configuration and login wiring

`db_oauth_provider()` performs workspace OIDC discovery at `/oidc/.well-known/openid-configuration`, enables PKCE, nonce and ID-token validation, and supports confidential or public client authentication. `db_shiny_config()` adds `openid`, `profile`, `email`, and `offline_access` to configured Databricks API scopes, defaults to `sql`, binds the client to that workspace's `/api/` resource base, and requires at least 40 seconds of remaining token lifetime. Sources: `../brickster/R/shiny-auth.R:16-31`, `:102-184`.

`db_shiny_ui()` and `db_shiny_server()` wrap shinyOAuth. The server defaults OAuth network operations to asynchronous, uses finite eight-hour authorization lifetime, and returns session helpers similar to Fabric. It requires shinyOAuth development APIs (`0.6.1.9000` in its runtime check) even though `DESCRIPTION` only suggests shinyOAuth `>= 0.6.1`. Sources: `shiny-auth.R:200-245`; `../brickster/DESCRIPTION:51-52`. The bridge needs accurate feature/version constraints, not the weaker declared constraint copied blindly.

The current Databricks convenience API assumes one workspace and uses `connection$access_token(required_scopes, ...)` without named target selection (`shiny-auth.R:279-283`). In a multi-backend bridge, the Databricks adapter should select an explicitly bound connection/target and preserve workspace identity. Multiple unrelated issuers should not be collapsed into one Entra login unless the target platform supports that exact flow.

### Generic callback provider: keep upstream

`db_token_provider(host, token)` is exported and Shiny-independent. Its callback accepts `force_refresh`; every actual request obtains a fresh token, including deferred requests. A provider is bound to an HTTPS workspace origin, does not cache callback tokens, rejects callback failures, and never falls back to environment, CLI, or service-principal credentials. Sources: `../brickster/R/package-auth.R:3-47`, `:56-83`.

Request construction checks workspace binding. `db_req_auth_token_provider()` uses httr2 OAuth signing with an intentionally empty token cache, disables redirects, and asks the callback for a forced refresh after a rejected `invalid_token` challenge clears its authentication cache. Sources: `package-auth.R:88-145`; `../brickster/R/request-helpers.R:27-87`. The generic hook is valuable beyond shinyOAuthDB and should remain in brickster. It would be a regression to replace it with only a hard dependency on the new Shiny package.

An existing shinyOAuth connection already works directly with this hook: the tests pass a callback around the captured connection's `access_token()` and verify refresh/logout behavior (`../brickster/tests/testthat/test-shiny-auth-offline-helpers.R:517-551`). This is the cleanest adapter starting point.

### Native DBI/dbplyr and query engines: keep upstream

brickster's DBI credential class union accepts `db_token_provider` alongside character and NULL. `dbConnect(DatabricksSQL(), token = provider, ...)` retains the provider in the connection and routes later API calls through it. The connection is a REST-backed stateless DBI handle: `dbDisconnect()` returns TRUE and `dbIsValid()` currently checks required fields, not remote identity or authorization. Sources: `../brickster/R/databricks-dbi.R:14-35`, `:100-103`, `:112-200`, `:208-235`.

Keep `DatabricksSQL()`, the S4 DBI classes/methods, dbplyr SQL translation, SQL statement execution/polling/cancellation/chunk fetching, Arrow result conversion, and Unity Catalog/staging logic in brickster. Public engines include `db_sql_query()` (`../brickster/R/sql-query-execution.R:784-835`), statement cancellation/status/results (`:143`, `:188`, `:236`), and dbplyr collection (`../brickster/R/databricks-dbplyr.R:541`). shinyOAuthDB should preserve their native connection classes and return objects.

brickster supports `INLINE` and `EXTERNAL_LINKS` result transport, defaulting DBI to external links (`databricks-dbi.R:92-96`, `:117`). The latter fetches signed result URLs and can remain usable independently of the main OAuth callback. The bridge must not claim logout cancels previously authorized statements or invalidates all already issued result capabilities. Backend-specific cancellation is a separate operation.

### Async task: useful shared implementation seed

`db_shiny_task()` is an exported wrapper over `shiny::ExtendedTask` + `mirai`. It acquires a fixed token asynchronously in the owning process, checks the captured generation before dispatch, passes explicit host/token/arguments to the worker, and envelopes **both successful results and errors** with generation. `result()` validates generation before returning the value or throwing the error; old completed outcomes appear as `initial`. It ignores invocations while busy and rejects credential overrides and use from another session. Sources: `../brickster/R/shiny-auth.R:339-513`, especially `:417-460`, `:466-510`.

The wrapper rebinds custom non-namespace functions to `baseenv()` before serialization (`:403-405`). That deliberately prevents capturing the application environment but is a user-visible restriction: ordinary closures relying on app variables will not work. A shared task API should expose an explicit operation descriptor or explicit data arguments and document worker dependency behavior. Do not silently serialize an OAuth connection, Shiny session, provider closure, DBI external pointer, or authenticated R6 item.

## Proposed ownership and migration map

### Public versus private boundaries

Use only public platform APIs from the bridge. Internal functions mentioned in this report explain why moving code requires care; they are not suggested calls via `:::`.

| Package | Public functions/hooks suitable for adapters | Internal functions that must not become bridge dependencies |
| --- | --- | --- |
| fabricQueryR | `fabric_shiny_token_provider` (`NAMESPACE:112`); Shiny convenience functions (`:110-113`); `fabric_sql_connect`, `fabric_sql_connection_info`, `fabric_sql_query` (`:115-118`); `fabric_item`, `fabric_items`, `fabric_workspaces` (`:44-45`, `:130`); `fabric_pbi_dax_query`, `fabric_kql_query`, `fabric_graphql_query`, `fabric_onelake_read_delta_table` (`:103`, `:60`, `:42`, `:88`). Public functions' `token` argument is the generic external-credential seam. | `fabric_credential`, `fabric_get_token`, `fabric_service_credential`, `fabric_shiny_profiles`, `fabric_shiny_provider`, `fabric_shiny_route`, `fabric_check_endpoint_policy`, `.httr2_perform`, `.fabric_sql_db_connect`, and Arrow ownership helpers. These are not exported in `../fabricQueryR/NAMESPACE`. |
| brickster | `db_token_provider` (`NAMESPACE:135`), `db_oauth_provider` (`:92`), `db_shiny_config/server/task/ui` (`:116-119`), `DatabricksSQL` (`:18`), `db_sql_query` (`:125`), statement execution/cancel/results/status (`:120-123`), exported DBI classes and methods (`:263-294`). | `db_request`, `db_req_auth_token_provider`, `db_auth_workspace_host`, `db_check_token_host`, `db_check_bearer_token`, `db_shiny_session`, SQL result/polling/conversion helpers. These are not exported in `../brickster/NAMESPACE`. |

`fabric_shiny_token_provider()` and the documented Databricks callback object are usable now. Constructing private Fabric credential objects or reproducing their internal lists in another package is a fragile shortcut. For a clean removal of Fabric's current adapter, agree and release a public generic policy/credential constructor upstream first.

| Existing component | Destination | Reason and migration shape |
| --- | --- | --- |
| Fabric `fabric_shiny_config/ui/server` | shinyOAuthDB | Backend presets plus shared Shiny lifecycle. Keep deprecated forwarding wrappers in fabricQueryR during transition. |
| Fabric existing-connection provider | shinyOAuthDB adapter, after generic policy seam | Capturing shinyOAuth connections is bridge behavior; enforcing generic supplied-token destinations is transport behavior. Preserve policy first. |
| Fabric `.fabric_audience`, credential adaptation, retry and endpoint checks | fabricQueryR | Ordinary platform APIs use them without Shiny. Refactor away `fabric_shiny_*` names/dependency where needed; do not remove behavior. |
| Fabric SQL/DAX/KQL/GraphQL/OneLake engines, discovery/R6 items | fabricQueryR | Tested platform implementation, public native API and result contracts. |
| Databricks OAuth provider preset | shinyOAuthDB adapter or upstream reusable discovery hook | Provider construction is thin; avoid depending on upstream Shiny wiring. Either keep `db_oauth_provider()` reusable or recreate discovery using shinyOAuth's public API. |
| Databricks `db_shiny_config/ui/server` | shinyOAuthDB | Same lifecycle responsibilities as Fabric; preserve wrappers initially. |
| Databricks `db_shiny_task` | shared shinyOAuthDB task implementation | Strong seed for generation checks, worker separation, busy behavior and stale-error masking. |
| Databricks `db_token_provider`, request signing, workspace/expiry checks | brickster | Generic external-auth hook required by REST and DBI; retain without a shinyOAuthDB dependency. |
| Databricks DBI/dbplyr, SQL engine and other REST APIs | brickster | Preserve native implementation, avoid copying Apache-licensed engines. |

Avoid a dependency cycle. shinyOAuthDB can optionally depend on fabricQueryR and brickster. If old convenience wrappers call shinyOAuthDB, they must do so through optional feature checks rather than making both sides hard Imports dependencies. An alternative is a supported overlap/deprecation window followed by removal of old wrappers in a major release; document the exact migration path.

## Critical behavior differences and pitfalls

1. **Expiry metadata differs, and per-target expiry is not public yet.** brickster fixed worker tokens carry `brickster_host` and `brickster_expires_at`; the transport rejects expiry within 40 seconds (`shiny-auth.R:275-276`, `package-auth.R:88-108`). This is compatible with its present single/default-target flow. Fabric fixed worker tokens carry service endpoint policy but currently no explicit expiry metadata (`fabric_shiny.R:170-189`). shinyOAuth's `summary()` selects the default target and its token expiry (`../shinyOAuth/R/classes__OAuthConnection.R:355-359`, `../shinyOAuth/R/methods__connection.R:124-139`); `targets()` exposes status/granted scopes/evidence but no per-target expiry (`../shinyOAuth/R/classes__OAuthConnection.R:558-589`). Do not read private records or pretend default-target expiry applies to a secondary token. Until an optional public per-target credential-metadata accessor is agreed upstream, derive a conservative worker-use deadline from acquisition **start** time plus requested `min_valid_for`, with a safety margin. Label this a bridge use deadline, not actual token expiry, and recheck it before dispatch/use. A shared snapshot should retain target, destinations, captured generation and that deadline. Acquisition time spent waiting must consume the budget. Platform revocation can still occur earlier, and native SQL sessions have their own authentication lifetime.
2. **Physical DBI sessions do not become refreshed tokens.** Fabric SQL acquires a token immediately before DBI connection (`fabric_sql_connect.R:422-469`); it returns the native driver connection and does not attach an OAuth callback that is consulted per statement. Databricks' REST-backed DBI handle does retain such a callback. Therefore refresh/logout cannot be promised to behave identically. Prefer per-operation connections for native drivers by default; offer explicitly session-owned reuse, cleanup on replacement/logout/session end, and backend-specific reconnection policies. Do not share a pool across user identities.
3. **A potential stale-error gap exists in the Fabric example.** The example envelopes only successful worker values and then calls `query$result()` before checking generation (`../fabricQueryR/inst/examples/shiny-fabric/app.R:133-151`, `:173-180`). Inference: after replacement login, a rejected operation from the previous login can be raised before its generation is checked. Existing example tests validate hidden old successful output and current failures (`../fabricQueryR/tests/testthat/test-shiny-example.R:115-158`), but do not establish stale-error masking after replacement. Use the Databricks value/error envelope pattern in the unified task.
4. **Provider and token attributes are part of real transport behavior.** A plain provider around `access_token()` can lose Fabric destination restrictions; a coerced Databricks fixed string can lose workspace/expiry metadata. Do not strip attributes in adapters or worker dispatch. Generic R attributes are not a sandbox against arbitrary R code; design explicit trusted operation descriptors and preserve underlying transport checks.
5. **Successful sign-in does not establish source access.** Fabric documents recorded scopes separately from remote item/SQL permissions (`fabric_shiny.R:31-35`, `fabric_shiny_config.R:37-38`). Errors for unauthenticated, unsupported target, missing scope, refresh pending, interaction required, forbidden endpoint, and database permission denial should remain distinct. Do not force refresh on every permission denial.
6. **Retry policies already exist downstream.** Fabric HTTP can force one retry after HTTP 401 even for non-idempotent operations, and transient retry separately requires idempotency (`fabric_shiny.R:59-61`, `../fabricQueryR/R/httr2_helpers.R:186-193`, `:299-306`). SQL statement retries are idempotency-sensitive (`fabric_sql_connect.R:798-817`). brickster has httr2 request retry plus one OAuth retry (`request-helpers.R:45-49`, `package-auth.R:125-144`). The bridge should not blindly add another retry loop over SQL mutations or whole data operations.
7. **Version numbers alone are currently insufficient evidence.** Fabric checks feature formals, brickster checks development version, and the local fork is not official upstream. Package startup/adapter validation should test the public required APIs once and give actionable installation guidance. Record the exact supported release/fork until upstream hooks are available.
8. **SQL writes remain governed remotely.** Fabric's SQL scope is `user_impersonation` and can permit writes if the user has grants (`fabric_shiny_config.R:37-38`). `read_only` connection hints or a convenience SELECT validator are not a substitute for platform grants. A data-access bridge should define its query/execute surface explicitly and preserve native permissions.

## Existing tests to carry or retain

The migration is supported by substantial behavioral tests. Move session/lifecycle tests with the bridge while retaining generic callback and engine tests upstream. Add bridge integration tests that exercise public boundaries instead of importing `:::` internals.

| Behavior | Existing exact source references |
| --- | --- |
| Fabric target resources, scope separation, combined Power BI target, validated Microsoft client | `../fabricQueryR/tests/testthat/test-fabric_shiny_config.R:1`, `:26`, `:48`, `:74`, `:100` |
| Fabric exact routing, unsupported targets before acquisition, endpoint policy retention, redirects, permission denial | `../fabricQueryR/tests/testthat/test-fabric_shiny_token_provider.R:1`, `:35`, `:76`, `:104`, `:148`, `:178`, `:210`, `:248`, `:266` |
| Fabric real module refresh/logout/replacement and foreign session isolation | `../fabricQueryR/tests/testthat/test-fabric_shiny.R:28`, `:325` |
| Fabric partial target failure and retry without replaying a data query | `../fabricQueryR/tests/testthat/test-fabric_shiny.R:134` |
| Fabric async token serialization, policy retention, late token rejection and failure propagation | `../fabricQueryR/tests/testthat/test-fabric_shiny_async.R:1`, `:66`, `:116` |
| Fabric workload tokens reaching actual DAX/GraphQL/KQL/OneLake transport seams | `../fabricQueryR/tests/testthat/test-fabric_shiny_services.R:1` |
| SQL protected options, fresh tokens on retries, parameter binding, Arrow resource ownership, retry idempotency and precision | `../fabricQueryR/tests/testthat/test-fabric_sql_connect.R:270`, `:304`, `:353`, `:397`, `:734`, `:770`, `:807`, `:1495`, `:1558`, `:1754`, `:2133`, `:2165` |
| Databricks original connection across refresh/logout/replacement/session end | `../brickster/tests/testthat/test-shiny-auth-offline-helpers.R:147`, `:183`, `:235`, `:258`, `:368`, `:517` |
| Databricks validated discovery/configuration and required scope readiness | `../brickster/tests/testthat/test-shiny-auth-offline-helpers.R:67`, `:91`, `:120`, `:211` |
| Databricks provider no fallback, host rejection, invalid-token bounded refresh and no refresh on 403 | `../brickster/tests/testthat/test-token-provider-offline-helpers.R:6`, `:36`, `:52`, `:80`, `:117`, `:144` |
| Databricks worker binding/expiry and DBI provider retention after authorization ends | `../brickster/tests/testthat/test-token-provider-offline-helpers.R:171`, `:195`, `:220` |
| Real mirai dispatch, late-token dispatch prevention, current errors/old values, owning-session checks | `../brickster/tests/testthat/test-shiny-task-offline-helpers.R:28`, `:71`, `:105`, `:144` |

Additional bridge tests should cover old **errors** after replacement login, per-source generation if multiple authorizations coexist, per-resource expiry in multi-token tasks, prohibited cross-user reuse of native connections, session cleanup, worker serialization preserving policy, and parameter/return-shape delegation without rewriting SQL. These target security-sensitive behavior and lifecycle boundaries rather than mirroring helper implementation.

## Dependency and licensing implications

Fabric is MIT (`../fabricQueryR/DESCRIPTION:18`, `../fabricQueryR/LICENSE:1-2`) and uses AzureAuth, httr2, R6, Arrow helpers, and reticulate as Imports. Database drivers, shinyOAuth, Shiny and async tools are optional Suggests (`DESCRIPTION:19-42`, `:51-64`). Keep the bridge's backend integrations optional; an Azure SQL app should not require Fabric's Python/Delta stack or a Databricks driver. A small required core can use shinyOAuth, Shiny >= 1.8.1 for ExtendedTask, promises, and simple validation. The chosen task executor can be an optional mirai >= 2.5.1 adapter as required by the existing Databricks implementation (`../brickster/R/shiny-auth.R:375-378`); `bslib >= 0.7.0` is only needed for optional task-button integration (`:407-414`). Azure SQL needs optional DBI/odbc and an installed Microsoft driver, not a new bridge driver. Each backend package can remain optional with early availability checks. For shinyOAuth, require the released public connection/target APIs once their release version is known; current Fabric feature checks and Databricks development-version checks show that CRAN `0.6.1` is insufficient for the complete bridge.

Fabric's ADBC path additionally needs an installed external `mssql` binary >= 1.5.0, and its documentation states that `adbi` is archived on CRAN and available from r-universe (`../fabricQueryR/R/fabric_sql_connect.R:187-201`, `:1069-1121`, `:1185-1224`). This is evidence about the local integration requirements, not an independent check of current distribution status. Treat ADBC as an explicit advanced option rather than a mandatory bridge dependency; verify current driver/package status separately before promising installation support.

brickster is Apache-licensed (`../brickster/DESCRIPTION:14`, `../brickster/LICENSE.md`) and imports DBI/dbplyr and its query infrastructure (`DESCRIPTION:18-38`); its Shiny/OAuth/async tools are optional (`:39-54`). Source copying from brickster requires preserving applicable license/attribution material: its checked-in license's redistribution section requires the license copy, notices and modified-file notices (`LICENSE.md:86-118`) and a NOTICE file exists (`../brickster/NOTICE`). Referencing brickster through its public R API avoids copying its engines. If transplanting task/session helper source, retain provenance and applicable notices or verify separately who owns the newly authored fork code before selecting shinyOAuthDB's license.

## Recommended first migration slice

1. Implement one bridge session abstraction that adapts existing shinyOAuth connections or its manager, with a source registry mapping sources to explicit connection/target/destination/adapter settings.
2. Add Fabric and Databricks adapters calling their public credential and engine hooks. Require the supported local features explicitly; do not imply official upstream release support yet.
3. Generalize the Databricks task's token acquisition, explicit worker arguments, generation envelope and stale-result/error suppression. Keep native returned data frame/tibble semantics. Add optional DBI connection/query escape hatches rather than making a new DBI driver for all databases.
4. Add a direct Azure SQL DBI/ODBC adapter using the token attribute mechanism already validated in Fabric, with managed endpoint/TLS/authentication options and per-operation cleanup. Handle other SQL Server and PostgreSQL authentication models only through explicitly supported backend-specific flows.
5. Prepare compatibility wrappers and extract any remaining Shiny-dependent endpoint policy machinery upstream. Delete duplicated Shiny wiring only after bridge behavior and old call migration are covered.

The highest-value reuse is the existing platform packages' public interfaces and tests. The highest-value new shared code is ownership/lifetime enforcement, source-to-target mapping, credential adaptation, worker dispatch, and a coherent user-facing API.
