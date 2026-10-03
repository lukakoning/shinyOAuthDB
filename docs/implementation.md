# Current implementation

shinyOAuthDB connects shinyOAuth authorizations to native database clients. Backend helpers return reactive accessors. Query execution, result caching, and background work belong to the native client and ordinary Shiny application code.

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

`con()` returns an ordinary native DBI connection. Fabric's `token()` returns a regular `function(audience, force_refresh)` callback accepted by fabricQueryR. Databricks' `token()` returns a bearer string accepted by upstream brickster. All OAuth adaptation and provider presets live here; neither database package needs Shiny integration or new credential hooks.

The sibling fabricQueryR checkout's former Shiny UI/server, provider adapter, and duplicate apps have been removed along with their optional dependencies. Its ordinary authentication and token callback API remain. Sandbox provisioning stays in that repository; the single app lives in this package's `playground/fabric` directory.

Each accessor belongs to one Shiny session. Its native connection is reused for the selected authorization and closes on authorization replacement, observed permission loss, or session end. Token providers stay pinned to their original grant and cannot follow another login.

The bridge asks shinyOAuth for the configured target, scopes, and minimum token validity. shinyOAuth remains responsible for login, consent, refresh, browser storage, and selecting retained authorizations. Native packages retain endpoint validation, query parameters, polling, pagination, and result conversion.

Ordinary token refresh preserves established SQL connections, including transactions and temporary tables. Upstream brickster's stateless DBI connection stores a bearer string; its accessor obtains a current token on each use and rebuilds the connection when that string changes. Call it per operation. Already returned native objects follow their package's lifetime semantics; brickster's `dbDisconnect()` does not revoke an issued token. The bridge prevents subsequent accessor use after logout but does not wrap native methods.

The Fabric callback checks the requested audience/scopes and forwards refresh to shinyOAuth. It adds no private credential attributes or package-specific class. Trusted endpoints are supplied by application configuration or native discovery, and transport behavior stays with fabricQueryR.

`oauth_db_connect()` accepts a native connector and fixed options, and supplies the bearer string in its named `token_arg`. `oauth_db_token()` supplies a reactive bearer-string accessor for other APIs. A new package needs no query registry entry or special callback interface.

## Shiny behavior

Calling the accessor creates an ordinary reactive dependency. A render function using it follows authorization changes. The bridge owns the connection/provider lifecycle only.

Resolve `connection <- con()` before calling a DBI generic. R's S4 dispatch can wrap a missing-authorization signal raised inside `DBI::dbGetQuery(con(), ...)` as an ordinary error. Evaluating the accessor first preserves Shiny's normal blank output before sign-in and after logout.

Results cached by `eventReactive()`, `reactiveVal()`, or another application cache keep their usual behavior. The bridge does not clear app-owned query results, associate errors with grants, cancel queries, or reject late background results. Apps that retain data across events or run background queries own that result lifecycle.

Remote grants and row policies remain enforced by the database. Local scope checks cannot detect every remote permission change.

## Configuration

Client helpers return ordinary shinyOAuth clients and are optional. They work with the existing single-authorization modules or retained connection manager. Microsoft exposes `provider`, `token_targets`, `default_token_target`, and `scopes` as replaceable defaults; Databricks and Snowflake expose `provider` and `scopes`. Remaining native client arguments pass through `...`. Explicit scopes and target lists replace their presets completely; they are not appended or merged. Keep each database accessor's `target` and `scopes` consistent with that configuration.

Provider-only configuration uses `shinyOAuth::oauth_provider_microsoft()`, `oauth_db_databricks_provider()`, or `oauth_db_snowflake_provider()`, followed by ordinary `shinyOAuth::oauth_client()`. Databricks uses shinyOAuth's OIDC discovery directly. Both local presets accept native provider settings through `...`. No database accessor or login module is created by these configuration helpers.

Connection presets avoid redundant configuration: SQL Server aliases the Azure SQL token transport, Databricks needs a host only for a DBI connection, and Snowflake derives the native OAuth scope from its role. Explicit Snowflake scopes and targets still support External OAuth.

The target-enabled development shinyOAuth API is required. The database packages use their existing interfaces. Offline tests verify native routing and connection lifecycle. The integrated Fabric app supports the persistent Shiny sandbox and visitor sign-in; its explicit shared-sandbox mode is an example-only AzureAuth path. Actual browser flows, database user mapping, and data permissions require deployment-specific verification.

The [README](../README.md) and [playground](../playground/README.md) describe this API. Earlier architecture and API-draft documents are historical. [Integration checks](../tests/integration/README.md) use deployment-supplied fixtures.
