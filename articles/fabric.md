# Microsoft Fabric

Microsoft Fabric stores and queries analytics data in warehouses,
lakehouses and other services. You can use that data in a Shiny app with
each visitor’s Microsoft account and existing access permissions.

Start with a SQL endpoint: a Warehouse, Lakehouse SQL endpoint or SQL
Database can supply a DBI connection for SQL and dbplyr queries. Later
in this guide, the same sign-in lets you call fabricQueryR functions to
list workspaces or read Lakehouse tables.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("fabric")` in the R console for
an editable local app. The launcher helps you find the SQL endpoint and
Microsoft app registration, then waits for **Run example query** before
querying.

Install `fabricQueryR`, `odbc`, `bslib`, `processx`, `askpass` and
Microsoft ODBC Driver 18 first. You need an existing Fabric item and
permission to use its data. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app)
for editing and
[`?oauth_db_cloud_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
for the launcher settings.

## Set up SQL access

Install [Microsoft ODBC Driver
18](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)
for your operating system too. Copy the server and database from the
item’s SQL connection settings. Users need access to that item and its
data; see [Fabric SQL
connectivity](https://learn.microsoft.com/en-us/fabric/data-warehouse/connectivity).

Create an Entra Web app registration with permission to access SQL on a
user’s behalf. Register `http://localhost:8100` as its redirect URI.
Save these values in a local `.Renviron` file and restart R:

``` text
OAUTHDB_TENANT_ID=your-tenant-id
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

Use the [Microsoft registration
steps](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html#register-a-microsoft-entra-app).
For this first SQL app, add **Azure SQL Database** delegated
`user_impersonation`. Fabric API permissions are needed only when adding
the API examples later in this guide.

| Value | Where to find it |
|----|----|
| `server` | Open the Warehouse or Lakehouse **SQL analytics endpoint**, then copy its **SQL connection string** server |
| `database` | The database/catalog shown in those connection settings |
| Tenant ID, client ID, secret | Your [Entra app registration](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html#register-a-microsoft-entra-app) |

Copy the server hostname, without a connection-string prefix or
credentials. Share the item with the app’s users and grant access to its
data. A workspace or item ID from the browser URL isn’t the SQL server
hostname.

## A complete app

Save this as `example.R`, replacing the server and database:

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = "sql",
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),

    actionButton("load", "Load rows"),
    tableOutput("rows")
  ),

  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE
  )

  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_fabric_sql(
    auth$connection,
    server = "example.datawarehouse.fabric.microsoft.com",
    database = "Reporting"
  )

  query_task <- oauth_db_task(con)

  observeEvent(input$load, {
    query_task$invoke("SELECT CURRENT_USER AS database_user")
  })

  output$rows <- renderTable(query_task$result())
}

runApp(
  shinyApp(ui, server, uiPattern = ".*", onStart = function() {
    mirai::daemons(2)

    onStop(function() mirai::daemons(0))
  }),
  port = 8100,
  launch.browser = FALSE
)

# Open the app in your regular browser at its registered redirect URI.
```

Run `source("example.R")` and open `http://localhost:8100`. Sign in to
run the query; signing out clears the output.

The query shows the database user. Replace it with SQL for your tables.
Call `con()` inside the reactive expression to get the DBI connection;
you can also use it with dbplyr.

## List workspaces

To list the workspaces a user can access, change the client’s services
to `services = c("sql", "fabric")`. The Fabric preset requests and
requires the delegated `Workspace.Read.All` and `Item.Read.All`
permissions. Add both to the Entra registration alongside SQL access,
even if this example only lists workspaces.

Add `verbatimTextOutput("workspaces")` to the UI and put this inside
`server()`:

``` r

fabric <- oauth_db_fabric_api(auth$connection, targets = c(fabric = "fabric"))

workspace_task <- oauth_db_task(fabric, method = "call")

observeEvent(input$load, {
  workspace_task$invoke(fabricQueryR::fabric_workspaces)
})

output$workspaces <- renderPrint(workspace_task$result())
```

Pass a fabricQueryR function and its arguments to `invoke()`. The client
supplies the user’s credentials and returns the function’s result.

## Choose additional services

Include the services your app uses in
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
and configure their delegated permissions in the Entra registration:

| `services` entry | Use it for                                          |
|------------------|-----------------------------------------------------|
| `"sql"`          | Warehouse, Lakehouse SQL endpoint, and SQL Database |
| `"fabric"`       | Workspace and item discovery                        |
| `"onelake"`      | OneLake files and tables                            |
| `"dax"`          | Semantic model queries                              |
| `"kql"`          | KQL queries                                         |
| `"graphql"`      | GraphQL queries                                     |

Users need access to each workspace and item they query. SQL, OneLake,
and semantic models have their own permissions.

For KQL, include `"kql"` in the client’s services. With `fabric` created
as above, replace the table output with:

``` r

fabric <- oauth_db_fabric_api(auth$connection, targets = c(kql = "kusto"))

kql_task <- oauth_db_task(fabric, method = "call")

observeEvent(input$load, {
  kql_task$invoke(
    fabricQueryR::fabric_kql_query,
    cluster = "https://example.kusto.fabric.microsoft.com",
    database = "Events",
    query = "Events | take 20"
  )
})

output$rows <- renderTable(kql_task$result())
```

## Read a Lakehouse table

Use `services = c("fabric", "onelake")` to discover a Lakehouse and read
its tables. Add these services to the client if you’re also using SQL.

`fabric_item()` returns a fabricQueryR object with methods such as
`$read_table()`. Look up that object and read its data inside the same
worker function, so a native resource never crosses processes:

``` r

fabric <- oauth_db_fabric_api(
  auth$connection,
  targets = c(fabric = "fabric", onelake = "storage")
)

read_orders <- function(client) {
  lakehouse <- fabricQueryR::fabric_item(
    fabricQueryR::fabric_item,
    workspace = "workspace-guid",
    item = "lakehouse-guid",
    token = client$token_provider()
  )

  lakehouse$read_table("Orders", limit = 100L)
}

lakehouse_task <- oauth_db_task(fabric, method = read_orders)

observeEvent(input$load, lakehouse_task$invoke())

output$rows <- renderTable(lakehouse_task$result())
```

Warehouse objects offer `$sql_query(sql)`, and semantic model objects
offer `$dax_query(dax)`. Include `"sql"` or `"dax"` in the client’s
services for those methods. See fabricQueryR’s help for their arguments.

## Connection options

The SQL helper uses ODBC by default, including SQL Server translations
for dbplyr. Set `timeout` and `read_only` on the helper if your app
needs different connection settings. For ADBC and Arrow connections, see
[`?oauth_db_fabric_sql`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md)
and
[`fabricQueryR::fabric_sql_connect()`](https://kennispunttwente.github.io/fabricQueryR/reference/fabric_sql_connect.html).

Call `con()` before each operation. ODBC keeps a valid database session
open through token renewal; ADBC replaces it on the next access. Consume
and close outstanding results before starting another operation. Your
app must also close any connections it opens directly through
fabricQueryR functions or resource methods.

## Use an existing sign-in

If your shinyOAuth client uses different token target names, map the
services to those targets:

``` r

fabric <- oauth_db_fabric_api(
  auth$connection,
  targets = c(fabric = "discovery", sql = "reporting", onelake = "files")
)
```

The mapping replaces the defaults. For one service without a named
target, use `targets = list(kql = NULL)`. DAX and GraphQL share the
Power BI resource and must use the same target; different resources need
different targets.

To call a fabricQueryR function directly, pass
`token = fabric$token_provider()`.
[`?oauth_db_fabric`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric.md)
shows the alternative for a single service.

See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions)
for target settings and saved query results.
