# Moving integration into shinyOAuthDB

shinyOAuth manages authorization. shinyOAuthDB passes that authorization to
ordinary database clients. Queries use those clients directly. See the
[current implementation](implementation.md) for connection lifetime details.

## fabricQueryR

The sibling checkout's development-only `fabric_shiny_config()`,
`fabric_shiny_ui()`, `fabric_shiny_server()`, and
`fabric_shiny_token_provider()` have been removed. The experimental
`fabric_token_provider()` constructor is also removed. Neither is required
by the bridge.

Use a native shinyOAuth client, optionally configured with
`oauth_db_microsoft_client()`, and shinyOAuth's own login module. Inside the
server, obtain a service-specific callback:

```r
token <- oauth_db_fabric(auth$connection, service = "kql")
output$rows <- shiny::renderTable({
  fabricQueryR::fabric_kql_query(
    cluster = "https://cluster.kusto.fabric.microsoft.com",
    database = "Reporting", query = "Sales | take 20", token = token()
  )
})
```

For a DBI SQL connection use `oauth_db_fabric_sql()`. Other Fabric operations
continue using their existing `token` argument. The callback is an ordinary
function accepting `audience` and `force_refresh`, with no provider class or
private credential attributes.

The [integrated Fabric app](../playground/fabric/README.md) replaces the separate
service examples and the old fabricQueryR apps. The persistent sandbox and its
guarded capacity workflows remain in fabricQueryR; launch the app from here.

## brickster

Use upstream brickster's scalar bearer `token` argument. Without a warehouse,
`oauth_db_databricks()` returns a bearer-string accessor. With `warehouse_id`,
it returns a native DBI connection accessor. Call the accessor for each
operation so token rotation and authorization changes are checked.

`oauth_db_databricks_provider()` performs discovery through shinyOAuth. Neither
provider discovery nor connection creation requires changes to brickster.

## Existing shinyOAuth configuration

Native providers, clients, and multiple authorizations remain usable. Presets
are optional and expose native configuration overrides. Bind each accessor to
its intended authorization; with the connection manager, choose an explicit
grant ID. Database accessors do not create or select login clients.

The old shinyOAuthDB source/query/task framework has no compatibility layer.
Use ordinary Shiny reactivity and the database package's query functions;
application-owned caching and background work remain application decisions.
