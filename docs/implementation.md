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

`con()` returns an ordinary native DBI connection. Fabric and Databricks also have provider accessors: `token()` returns the native package's token provider, which is passed directly to that package's functions.

Each accessor belongs to one Shiny session. Its native connection is reused for the selected authorization and closes on authorization replacement, observed permission loss, or session end. Token providers stay pinned to their original grant and cannot follow another login.

The bridge asks shinyOAuth for the configured target, scopes, and minimum token validity. shinyOAuth remains responsible for login, consent, refresh, browser storage, and selecting retained authorizations. Native packages retain endpoint validation, query parameters, polling, pagination, and result conversion.

Ordinary token refresh preserves an established DBI connection, including its transactions and temporary tables. The accessor reopens an invalid native connection or creates a new one for a replacement authorization. Native drivers remain responsible for established-connection credential behavior.

`oauth_db_connect()` accepts a native connector and fixed options, and supplies the bearer string in its named `token_arg`. `oauth_db_token()` supplies a reactive bearer-string accessor for other APIs. A new package needs no query registry entry or special callback interface.

## Shiny behavior

Calling the accessor creates an ordinary reactive dependency. A render function using it follows authorization changes. The bridge owns the connection/provider lifecycle only.

Results cached by `eventReactive()`, `reactiveVal()`, or another application cache keep their usual behavior. The bridge does not clear app-owned query results, associate errors with grants, cancel queries, or reject late background results. Apps that retain data across events or run background queries own that result lifecycle.

Remote grants and row policies remain enforced by the database. Local scope checks cannot detect every remote permission change.

## Configuration

Client helpers return ordinary shinyOAuth clients and are optional. They work with the existing single-authorization modules or retained connection manager. Microsoft exposes `provider`, `token_targets`, `default_token_target`, and `scopes` as replaceable defaults; Databricks and Snowflake expose `provider` and `scopes`. Remaining native client arguments pass through `...`. Explicit scopes and target lists replace their presets completely; they are not appended or merged. Keep each database accessor's `target` and `scopes` consistent with that configuration.

Provider-only configuration uses `shinyOAuth::oauth_provider_microsoft()`, `brickster::db_oauth_provider()`, or `oauth_db_snowflake_provider()`, followed by ordinary `shinyOAuth::oauth_client()`. The Snowflake preset accepts native provider settings through `...`; supplied endpoints, authentication settings, and other fields replace preset defaults. No database accessor or login module is created by these configuration helpers.

The documented development hooks in shinyOAuth, fabricQueryR and the brickster fork are required. Offline tests verify native routing and connection lifecycle. Actual browser flows, database user mapping, and data permissions require deployment-specific verification.

The [README](../README.md) and [playground](../playground/README.md) describe this API. Earlier architecture and API-draft documents are historical. [Integration checks](../tests/integration/README.md) use deployment-supplied fixtures.
