# shinyOAuthDB

Use a Shiny visitor's **shinyOAuth** authorization with DBI, **fabricQueryR**, **brickster**, or another database client.

A backend helper returns a reactive accessor to a native connection or credential. Call it from ordinary Shiny code, then use the database package directly. shinyOAuth handles login and refresh; the database package handles queries and results.

## A complete Azure SQL app

Set `OAUTHDB_TENANT_ID`, `OAUTHDB_CLIENT_ID`, `OAUTHDB_CLIENT_SECRET`, `OAUTHDB_SERVER`, and `OAUTHDB_DATABASE`. Register `http://localhost:8100` as the OAuth redirect URI.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)

ui <- oauth_ui(fluidPage(
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_azure_sql(auth$connection,
    server = Sys.getenv("OAUTHDB_SERVER"),
    database = Sys.getenv("OAUTHDB_DATABASE"))
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT TOP (20) name FROM sys.tables")
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

`con()` is a native DBI connection. Use it with DBI, dbplyr, or the driver's own API. The connection belongs to this Shiny session and selected authorization; the bridge closes it when either ends. The database enforces the user's permissions.

## Fabric and Databricks

Fabric accepts an ordinary token callback supplied by this package:

```r
# Configure the OAuth client with services = "kql".
# Inside server(), after creating auth:
token <- oauth_db_fabric(auth$connection, service = "kql")
output$rows <- renderPrint({
  credential <- token()
  fabricQueryR::fabric_kql_query(
    cluster = "https://example.kusto.fabric.microsoft.com",
    database = "Events", query = "Events | take 10", token = credential
  )
})
```

The [integrated Fabric app](playground/fabric/README.md) discovers the persistent Shiny sandbox and demonstrates SQL, DAX, KQL, OneLake, GraphQL, and discovery in one app.

The [Databricks app](playground/example-databricks.R) passes the bearer string from `token()` directly to upstream `brickster::db_sql_query()`. Passing `warehouse_id` to `oauth_db_databricks()` instead returns a native DBI connection accessor. Call it for each operation: brickster stores a fixed token, so the accessor replaces that connection when the credential rotates.

Queries retain their native arguments, return values, and errors. There is no query callback API, query registry, or task system.

## Available bindings

| Helper | Native value returned by its accessor |
|---|---|
| `oauth_db_azure_sql()`, `oauth_db_sql_server()` | DBI + odbc connection; SQL Server must support Entra |
| `oauth_db_azure_postgres()` | DBI + RPostgres connection; Azure Entra token as password |
| `oauth_db_fabric_sql()` | fabricQueryR SQL connection |
| `oauth_db_fabric(service = ...)` | Ordinary callback for fabricQueryR's existing `token` argument |
| `oauth_db_databricks()` | Bearer string for brickster, or DBI connection with a warehouse |
| `oauth_db_snowflake()` | DBI + odbc connection with OAuth |

Create accessors inside `server()`. Pass `auth$connection` directly, or an accessor selecting an explicit connection-manager ID. The [multiple authorization app](playground/example-multiple-connections.R) demonstrates selecting among retained grants.

## Several authorizations at once

Register your native clients with a normal shinyOAuth connection manager. Each database accessor can follow a different selected grant, including grants from different client registrations or providers:

```r
# Inside server(); manager contains your configured SQL and Fabric clients.
auth <- oauth_connections_server("authorizations", manager)
con_sql <- oauth_db_azure_sql(
  function() auth$connection(req(input$sql_authorization_id)),
  server = "example.database.windows.net", database = "Reporting"
)
token_kql <- oauth_db_fabric(
  function() auth$connection(req(input$kql_authorization_id)), service = "kql"
)
```

Populate both selectors with the `connection_id` values returned by `auth$connections()`. These are authorization IDs, not client profile names such as `"sql"`. Both accessors can be used simultaneously; disconnecting one grant leaves the other accessor bound to its own grant.

## Control providers and clients

Client helpers are optional presets returning ordinary shinyOAuth clients, usable with its usual modules and managers. Microsoft accepts explicit `provider`, `token_targets`, `default_token_target`, and `scopes`; Databricks and Snowflake accept explicit `provider` and `scopes`. Other native `oauth_client()` settings pass through `...`. Explicit values replace defaults rather than being merged. Match each backend accessor's `target` and `scopes` to your client configuration.

For provider-only setup, use `shinyOAuth::oauth_provider_microsoft()`, `oauth_db_databricks_provider()`, or `oauth_db_snowflake_provider()`, then construct the client yourself:

```r
provider <- oauth_db_snowflake_provider("account.snowflakecomputing.com")
client <- shinyOAuth::oauth_client(
  provider = provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("session:role:READER", "refresh_token"),
  label = "Reporting"
)
```

The Snowflake and Databricks provider presets accept native provider settings through `...`. Databricks discovery uses shinyOAuth directly. Native Snowflake OAuth and external OAuth use their respective identity-provider configurations.

## Another database client

Pass a native connection function and name its credential argument:

```r
con <- oauth_db_connect(auth$connection,
  connect = DBI::dbConnect,
  drv = MyDriver::Driver(), host = "database.example.com",
  token_arg = "access_token", scopes = "data.read"
)
output$rows <- renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT name FROM products")
})
```

`MyDriver` represents a driver that accepts delegated bearer tokens. Fixed options go directly to its native connector; `token_arg` names the argument receiving the user's token. DBI connections close automatically. Other native clients can supply `disconnect = TheirPackage::disconnect` when needed.

For an API that accepts a bearer string directly, `token <- oauth_db_token(auth$connection, scopes = "data.read")` supplies that string through `token()`.

## Ordinary Shiny behavior

The native accessor is reactive. A `renderTable()`, `renderPrint()`, or `reactive()` that calls it follows the selected authorization. Use regular Shiny tools for input dependencies, events, progress, caching, and background work.

Application-owned caches and `eventReactive()` keep their usual Shiny behavior. The bridge does not clear query results stored by the app or manage queries already in progress. Applications that retain results across events must handle their authorization lifecycle.

## Installation and examples

This development version requires matching **shinyOAuth** support for module-managed access tokens and token targets. Fabric uses **fabricQueryR**'s existing token callback API (tested with 1.0.1, before its Shiny integration). Databricks uses upstream **brickster** (tested with 0.2.14). No fork, Shiny helpers, or new credential hooks in either database package are required. The sibling fabricQueryR checkout's former Shiny helpers and duplicate apps have been removed; its persistent sandbox now points to the [integrated app here](playground/fabric/README.md).

From sibling checkouts, install the packages needed for your backend:

```sh
R CMD INSTALL ../shinyOAuth
R CMD INSTALL ../fabricQueryR   # Fabric only
# Databricks: install upstream databrickslabs/brickster, not a modified fork.
R CMD INSTALL .
```

Install your database driver separately. Install `RSQLite` for the local demonstration:

```r
pkgload::load_all()
source("playground/example-offline.R")
```

The offline app uses simulated A/B grants and seeded SQLite rows to demonstrate native connection reuse and cleanup. It does not test a real OAuth exchange. [Playground setup](playground/README.md) lists the complete apps and deployment settings. Live user mapping and database permissions require verification against your deployment.

## Breaking redesign

Replace source construction plus `oauth_db_session()` with a backend accessor such as `con <- oauth_db_azure_sql(auth$connection, ...)`, then call native database functions with `con()`. Source descriptors, operation mappings, managed query results, and worker execution have been removed.

[Implementation notes](docs/implementation.md) describe the bridge's boundaries. [Opt-in cloud checks](tests/integration/README.md) and the [PostgreSQL/Keycloak fixture](integration/postgres-keycloak/README.md) cover deployment-specific integration. Older architecture and API-draft documents record the previous design.

Run `testthat::test_local()` for package tests and `Rscript tools/check-playground.R --test` for source-checkout example checks.
