# shinyOAuthDB

Use a Shiny visitor's **shinyOAuth** authorization with DBI, **fabricQueryR**, **brickster**, or another database client.

Let visitors sign in with their own account and query data they are allowed to access. shinyOAuth handles login and token renewal; this package supplies the connection or credential; the database package runs your usual queries.

Start with the [simple apps vignette](vignettes/simple-apps.Rmd): one small app, then short examples for each Fabric interface, Databricks, Azure SQL/PostgreSQL, SQL Server, and Snowflake. After installing with vignettes, open it with `vignette("simple-apps", package = "shinyOAuthDB")`.

## A complete Azure SQL app

This example needs odbc and Microsoft ODBC Driver 18 for SQL Server, an Entra Web app registration with delegated SQL permissions, and database access for the visitor. See [installation](#installation-and-examples) for package setup.

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

Pass **`auth$connection` without parentheses** when creating the helper. This lets it follow sign-in and sign-out. `con` is the function you call later; **`con()` returns the native DBI connection**. Resolve it inside a render or reactive expression, then query with DBI, dbplyr, or the driver's own API.

The connection belongs to this Shiny session and selected authorization; the bridge closes it when either ends. The database enforces the user's permissions.

Already using shinyOAuth? Keep your client, UI, and login module. Add only the
database block. For a client without named token targets, use `target = NULL`:

```r
con <- oauth_db_azure_sql(auth$connection,
  server = "example.database.windows.net", database = "Reporting", target = NULL)
```

If your client names its SQL target `reporting`, use `target = "reporting"`
instead. Its consent must already cover SQL; the helper does not request new
permissions or change your provider. Missing permissions display a message;
target and authorization-selection errors remain available to the app.

## Fabric and Databricks

Fabric accepts an ordinary token callback supplied by this package:

```r
# Configure the OAuth client with services = "kql".
# Inside server(), after creating auth:
token <- oauth_db_fabric(auth$connection, service = "kql")
output$rows <- renderPrint({
  fabricQueryR::fabric_kql_query(
    cluster = "https://example.kusto.fabric.microsoft.com",
    database = "Events", query = "Events | take 10", token = token()
  )
})
```

The [integrated Fabric app](playground/fabric/README.md) discovers the persistent Shiny sandbox and demonstrates SQL, DAX, KQL, OneLake, GraphQL, and discovery in one app.

The [Databricks app](playground/example-databricks.R) uses `oauth_db_token(auth$connection, required_scopes = "all-apis")` and passes its bearer string directly to upstream `brickster::db_sql_query()`. For DBI, use `oauth_db_databricks()` with `host` and either `warehouse_id` or the native `http_path`. Call the accessor for each operation: brickster stores a fixed token, so the accessor replaces that connection when the credential rotates.

For Entra REST access, use `oauth_db_token(auth$connection, target = "databricks", required_scopes = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/user_impersonation")`, matching the Microsoft client's configuration.

Queries retain their native arguments, return values, and errors. There is no query callback API, query registry, or task system.

## Available bindings

| Helper | Native value returned by its accessor |
|---|---|
| `oauth_db_azure_sql()`, `oauth_db_sql_server()` | DBI + odbc connection; SQL Server must support Entra |
| `oauth_db_azure_postgres()` | DBI + RPostgres connection; Azure Entra token as password |
| `oauth_db_fabric_sql()` | fabricQueryR SQL connection |
| `oauth_db_fabric(service = ...)` | Ordinary callback for fabricQueryR's existing `token` argument |
| `oauth_db_databricks()` | DBI connection through brickster; accepts a warehouse ID or HTTP path |
| `oauth_db_token()` | Bearer string for brickster REST or another native API |
| `oauth_db_snowflake()` | DBI + odbc connection with OAuth |

Create accessors inside `server()`. Pass `auth$connection` directly, or an accessor selecting an explicit connection-manager ID. The [multiple authorization app](playground/example-multiple-connections.R) demonstrates selecting among retained grants.

Snowflake's native OAuth scope follows `role` automatically; set `required_scopes` explicitly for External OAuth. SQL Server uses the same connection helper as Azure SQL and requires Entra support on the server.

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

The [two-provider app](playground/example-two-authorizations.R) includes complete
Azure SQL and Databricks client registrations, callback routes, selectors, and
independent queries. It uses shinyOAuth's existing connection manager.

## Control providers and clients

Client helpers are optional presets returning ordinary shinyOAuth clients, usable with its usual modules and managers. Microsoft accepts explicit `provider`, `token_targets`, `default_token_target`, and `scopes`; Databricks and Snowflake accept explicit `provider` and `scopes`. Other native `oauth_client()` settings pass through `...`. Explicit values replace defaults rather than being merged. Match each backend accessor's `target` and `required_scopes` to your client configuration.

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

Already using shinyOAuth? Keep your client and login module and add a database helper. If your client has no named token targets, set `target = NULL`; otherwise use the name you configured in `token_targets`. The helper's `required_scopes` checks granted permissions; `scopes` requests consent on the client.

## Another database client

Pass a native connection function and name its credential argument:

```r
con <- oauth_db_connect(auth$connection,
  connect = DBI::dbConnect,
  drv = MyDriver::Driver(), host = "database.example.com",
  token_arg = "access_token", required_scopes = "data.read"
)
output$rows <- renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT name FROM products")
})
```

`MyDriver` represents a driver that accepts delegated bearer tokens when opening
a connection. Fixed options go directly to its native connector; `token_arg`
names the argument receiving the user's token. The generic helper reuses the
connection through token rotation. It does not update credentials inside a
cached SDK client. Non-DBI connections may supply
`disconnect = TheirPackage::disconnect`; their validity checks belong to the
native package.

For an API that accepts a bearer string directly, `token <- oauth_db_token(auth$connection, required_scopes = "data.read")` supplies that string through `token()`.

## Ordinary Shiny behavior

The native accessor is reactive. A `renderTable()`, `renderPrint()`, or `reactive()` that calls it follows the selected authorization. Use regular Shiny tools for input dependencies, events, progress, caching, and background work.

Application-owned caches and `eventReactive()` keep their usual Shiny behavior. The bridge does not clear query results stored by the app or manage queries already in progress. Applications that retain results across events must handle their authorization lifecycle.

The [query-button app](playground/example-query-button.R) runs only when clicked.
It clears its stored rows when the selected authorization changes or loses
permissions, and shows query errors in the output. A token refresh alone does
not clear the result or rerun the query.

Resolve `con()` or `token()` for each operation. Logout prevents subsequent
accessor use and attempts native cleanup. Already returned values retain native
behavior: a copied bearer string is not revoked, and upstream brickster's
stateless `dbDisconnect()` leaves a saved handle usable with its stored token.
The bridge does not wrap native methods. Its Fabric callbacks do reject use
after their original authorization ends or is replaced.

Token lifetime checks apply when acquiring a credential, not for an entire
query. Accessors acquire tokens synchronously in the owning Shiny session;
`refresh_pending` can occur if shinyOAuth is already refreshing asynchronously.
Handle recovery with shinyOAuth and run background work using the native
package's supported transport, with app-owned result checks.

## Installation and examples

This development version requires **shinyOAuth >= 0.6.1.9000**, including its
module-managed `access_token()`, `has_scopes()`, and `targets()` interfaces.
Fabric uses **fabricQueryR >= 1.0.1**'s existing token callback API. Databricks
uses upstream **brickster >= 0.2.14**. These are the tested minimum versions;
no fork, Shiny helpers, or new credential hooks in either database package are
required.

Install from the upstream repositories, then install the optional backend you
use:

```r
install.packages("remotes")
remotes::install_github("lukakoning/shinyOAuth")
remotes::install_github("lukakoning/shinyOAuthDB", dependencies = NA)

# Fabric only:
remotes::install_github("kennispunttwente/fabricQueryR")
# Databricks only:
remotes::install_github("databrickslabs/brickster")
```

For a local shinyOAuthDB checkout, use `R CMD INSTALL .` after installing its
dependencies. No sibling checkout is needed. For reproducible validation,
fabricQueryR 1.0.1 at commit `c6523dec95a4520e2acdc88e574465e8bf8b33b4` and
brickster 0.2.14 at `8a56667f15494d7e01d880d0815e9b213ffce1b8` provide the
unmodified native APIs used by the tests; `remotes::install_github()` accepts
`owner/repo@commit`.

Install your database driver separately. Install `RSQLite` for the local demonstration:

```r
pkgload::load_all()
source("playground/example-offline.R")
```

The offline app uses simulated A/B grants and seeded SQLite rows to demonstrate native connection reuse and cleanup. It does not test a real OAuth exchange. [Playground setup](playground/README.md) lists the complete apps and deployment settings. Live user mapping and database permissions require verification against your deployment.

[Implementation notes](docs/implementation.md) describe the bridge's boundaries.
[Migration notes](docs/migration.md) cover earlier development APIs.
[Opt-in cloud checks](tests/integration/README.md) and the
[PostgreSQL/Keycloak fixture](integration/postgres-keycloak/README.md) cover
deployment-specific integration.

Run `testthat::test_local()` for package tests and `Rscript tools/check-playground.R --test` for source-checkout example checks.
