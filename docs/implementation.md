# Current implementation

shinyOAuthDB connects shinyOAuth authorizations to native database clients. Backend helpers return reactive accessors. Query execution, result caching, and background work belong to the native client and ordinary Shiny application code.

## Source layout

Each backend owns its connection helpers, native factories, OAuth recipes,
provider/client presets, and protected driver options in one file:

| File | Responsibility |
|---|---|
| `R/backend__sql_server.R` | Azure SQL and Entra-enabled SQL Server |
| `R/backend__postgres.R` | Azure PostgreSQL |
| `R/backend__fabric.R` | Fabric SQL and native Fabric callbacks |
| `R/backend__databricks.R` | Databricks connections, OAuth presets, and token rotation policy |
| `R/backend__snowflake.R` | Snowflake connections and OAuth presets |
| `R/backend__microsoft.R` | Microsoft client composition and consent-scope handling |

The Microsoft preset composes recipes supplied by those backend files; it
does not duplicate their resources or permissions. Fabric reuses SQL Server's
OAuth recipe for SQL access.

Shared files contain no backend names, service tables, or driver policies.
`session.R` owns session lifetime and native-value reuse; `authorization.R`
consumes shinyOAuth's connection protocol; `auth.R` constructs native clients;
`options.R` validates names against the calling backend's policy; `odbc.R`
validates connection-string values for the shared ODBC transport; and
`conditions.R` supplies common validation and errors. Backends call these
utilities, never the reverse. The optional internal `cache_key` callback lets
a backend decide when its native value needs rebuilding.

Adding a backend does not require changing the shared lifecycle or validators.
If it uses the Microsoft client preset, add its recipe to that provider's
composition function as well.

## Native accessors

Create a backend accessor inside a Shiny session:

```r
con <- oauth_db_azure_sql(auth$connection,
  server = "example.database.windows.net", database = "Reporting")
output$rows <- renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT name FROM sys.tables")
})
```

The authorization input is a modern shinyOAuth connection, a reactive, or an accessor such as `auth$connection`. With a connection manager, select an explicit grant ID.

Several accessors can coexist in one session, each bound to its own authorization from any configured client registration or provider. Use the opaque `connection_id` returned by `auth$connections()` when calling `auth$connection(id)`; manager client profile names do not identify grants. Disconnecting one grant closes its connections without selecting another grant or retiring unrelated accessors.

`con()` returns an ordinary native DBI connection. Fabric's `token()` returns a regular `function(audience, force_refresh)` callback accepted by fabricQueryR. `oauth_db_token()` returns an accessor for bearer strings accepted by upstream brickster REST and other native APIs. `oauth_db_databricks()` always supplies a DBI connection, accepting either `warehouse_id` or `http_path`. All OAuth adaptation and provider presets live here; neither database package needs Shiny integration or new credential hooks.

The integrated Fabric app lives in `playground/fabric`. It uses fabricQueryR's
native token callback API; no Shiny integration in that package is needed.

Each accessor belongs to one Shiny session. Its native connection is reused for the selected authorization. Logout, replacement, observed required permission loss, or session end retires the cached value and attempts native cleanup. Native cleanup errors do not restore availability. Token callbacks stay pinned to their original grant and cannot follow another login. Previously returned native handles and strings retain their native lifetime; the accessor cannot revoke copied credentials or intercept methods called on saved handles.

Scope checks cover the helper's requirements; public `summary()` or selected
`targets()` status also detects missing client or target requirements. Once
reported, that denial remains in effect until upstream reports restored access.
An expired status alone does not retire established SQL sessions or force a
token refresh. Upstream can report expiry before insufficient scope, so the
bridge cannot detect a previously unreported client-policy denial hidden by
expiry without acquiring another credential.

The bridge asks shinyOAuth for the configured `target`, `required_scopes`, and minimum token validity. shinyOAuth remains responsible for login, consent, refresh, browser storage, and selecting retained authorizations. Native packages retain endpoint validation, query parameters, polling, pagination, and result conversion. Calls use the public connection methods directly; the supported shinyOAuth baseline accepts named targets.

Microsoft backends keep `/.default` consent in the shinyOAuth client and target
configuration. They check actual operation scopes when supplied, without
requiring the consent marker to appear among granted permissions. Generic
accessors forward their required scopes unchanged to shinyOAuth.

Ordinary token refresh preserves established SQL connections, including transactions and temporary tables. Upstream brickster's stateless DBI connection stores a bearer string; its accessor obtains a current token on each use and rebuilds the connection when that string changes. Call it per operation. Already returned native objects follow their package's lifetime semantics; brickster's `dbDisconnect()` does not revoke an issued token. The bridge prevents subsequent accessor use after logout but does not wrap native methods.

The Fabric callback checks the requested audience/scopes and forwards refresh to shinyOAuth. It adds no private credential attributes or package-specific class. Trusted endpoints are supplied by application configuration or native discovery, and transport behavior stays with fabricQueryR.

`oauth_db_connect()` accepts a native connector and fixed options, and supplies the bearer string in its named `token_arg` when opening a connection. It is intended for connection-time authentication. It does not update tokens stored inside cached SDK clients, and only DBI values receive automatic validity checks. `oauth_db_token()` supplies a fresh bearer string for each native API operation. Backend-specific renewal policies belong in the backend file. A new package needs no query registry entry or special callback interface.

Credential acquisition uses shinyOAuth's synchronous public accessor. Its
`min_valid_for` check is an acquisition-time guarantee, not a whole-query
deadline. Before returning a credential or opening a connection, an accessor
handles `refresh_pending` with a silent Shiny wait and depends on public status
until acquisition succeeds. A normal reactive consumer then resumes; successful
consumers do not depend on ordinary token rotation. Event-bound code still needs
another event. Fabric checks credential availability before handing out its
callback. Errors from that callback inside a native operation propagate without
creating a refresh dependency or scheduling replay. Other acquisition errors
remain available to the application. Accessors run in the owning Shiny session,
not a worker.

## Shiny behavior

Calling the accessor creates an ordinary reactive dependency. A render function using it follows authorization changes. The bridge owns the connection/provider lifecycle only.

Resolve `connection <- con()` before calling a DBI generic. R's S4 dispatch can wrap a missing-authorization signal raised inside `DBI::dbGetQuery(con(), ...)` as an ordinary error. Evaluating the accessor first preserves Shiny's normal blank output before sign-in and after logout.

Results cached by `eventReactive()`, `reactiveVal()`, or another application cache keep their usual behavior. The bridge does not clear app-owned query results, associate errors with grants, cancel queries, or reject late background results. Apps that retain data across events or run background queries own that result lifecycle.

Remote grants and row policies remain enforced by the database. Local scope checks cannot detect every remote permission change.

## Configuration

Client helpers return ordinary shinyOAuth clients and are optional. They work with the existing single-authorization modules or retained connection manager. Microsoft exposes `provider`, `token_targets`, `default_token_target`, and `scopes` as replaceable defaults; Databricks and Snowflake expose `provider` and `scopes`. Remaining native client arguments pass through `...`. Explicit scopes and target lists replace their presets completely; they are not appended or merged. Keep each database accessor's `target` and `required_scopes` consistent with that configuration.

Provider-only configuration uses `shinyOAuth::oauth_provider_microsoft()`, `oauth_db_databricks_provider()`, or `oauth_db_snowflake_provider()`, followed by ordinary `shinyOAuth::oauth_client()`. Databricks uses shinyOAuth's OIDC discovery directly. Both local presets accept native provider settings through `...`. No database accessor or login module is created by these configuration helpers.

Connection presets avoid redundant configuration: SQL Server aliases the Azure SQL token transport, Databricks REST uses the generic bearer accessor without a host, and Snowflake derives the native OAuth scope from its role. Explicit Snowflake scopes and targets still support External OAuth.

The target-enabled development shinyOAuth API is required. The database packages use their existing interfaces. Offline tests verify native routing and connection lifecycle. The integrated Fabric app supports the persistent Shiny sandbox and visitor sign-in; its explicit shared-sandbox mode is an example-only AzureAuth path. Actual browser flows, database user mapping, and data permissions require deployment-specific verification.

The [README](../README.md) and [playground](../playground/README.md) describe this API.
[Migration notes](migration.md) describe earlier development APIs.
[Integration checks](../tests/integration/README.md) use deployment-supplied fixtures.
