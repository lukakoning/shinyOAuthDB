# Databricks

Databricks is a hosted data and analytics platform. Its SQL warehouses
provide the compute that runs queries against your tables. With
shinyOAuthDB, visitors sign in with their Databricks account and query
the data their account can access.

[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md)
opens a DBI connection to a warehouse, so you can use SQL or dbplyr in
your app. Later examples use the same sign-in to call Databricks APIs
through the brickster package.

## Try the guided demo

Run this in the R console for an editable app that walks through setup:

``` r

install.packages(c("brickster", "jsonlite", "processx", "askpass", "bslib"))
shinyOAuthDB::oauth_db_cloud_demo("databricks")
```

The launcher asks for your workspace URL and OAuth app registration.
Sign in, choose a SQL warehouse, then click **Run example query** to
check your Databricks user. You need **CAN USE** on the warehouse.
Queries can start a stopped warehouse and consume compute credits;
stopping the local app leaves shared cloud compute running.

This demo requests SQL access, while the preset below also allows API
calls. Databricks Free Edition doesn’t provide the custom OAuth
registration it needs; see the [Free Edition
limits](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations).
For registration choices, warehouse settings and resuming an app, see
[`?oauth_db_cloud_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
and [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app).

## Register the app

Install `brickster` in R. In the Databricks account console, an
administrator registers a [custom OAuth
application](https://docs.databricks.com/aws/en/integrations/enable-disable-oauth)
under **Settings \> App connections \> Add connection**. For the preset
below, allow **All APIs** and `offline_access`, register
`http://localhost:8100`, and generate a client secret.

Save the client ID and secret in a local `.Renviron` file and restart R:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

| App value | Where to find it |
|----|----|
| `host` | Your workspace browser address, e.g. `example.cloud.databricks.com` |
| `warehouse_id` | Workspace **SQL Warehouses \> your warehouse \> Connection details**; also the last part of its HTTP path |
| Client ID and secret | The account console’s custom app connection |

Give users **CAN USE** on the warehouse and the appropriate catalog,
schema and table privileges.

## A complete app

Save this as `example.R`. Replace the workspace host and copy the
warehouse ID from the warehouse’s connection details:

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

host <- "example.cloud.databricks.com"
client <- oauth_db_databricks_client(
  host = host,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_databricks(
    auth$connection,
    host = host,
    warehouse_id = "warehouse-id"
  )

  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user()")
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*"),
  port = 8100,
  launch.browser = FALSE
)

# Open the app in your regular browser at http://localhost:8100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
```

Run `source("example.R")` and open `http://localhost:8100`. Sign in to
run the query; signing out clears the output.

The query shows the Databricks user. Replace it with SQL for your
tables. For dbplyr, get `connection <- con()` first, then pass it to
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html).

## Call brickster functions

To list warehouses, add `verbatimTextOutput("warehouses")` to the UI and
this code inside `server()`:

``` r

databricks <- oauth_db_databricks_api(auth$connection, host = host)

output$warehouses <- renderPrint({
  databricks$call(brickster::db_sql_warehouse_list)
})
```

Pass the function and its usual arguments to `$call()`. The client
supplies the workspace host and the user’s current token.

For example, to use brickster’s query API, replace the table output with
`verbatimTextOutput("rows")` and the render expression with:

``` r

output$rows <- renderPrint({
  databricks$call(
    brickster::db_sql_query,
    warehouse_id = "warehouse-id",
    statement = "SELECT current_user()",
    disposition = "INLINE",
    show_progress = FALSE
  )
})
```

This returns brickster’s query result. Use the DBI helper above when you
want
[`DBI::dbGetQuery()`](https://dbi.r-dbi.org/reference/dbGetQuery.html)
to return a data frame.

## Connection options

Supply `http_path = "/sql/1.0/warehouses/warehouse-id"` instead of
`warehouse_id` if you have the HTTP path. Set `catalog` and `schema` to
choose SQL defaults; other connection options go to brickster.

Call `con()` before each operation. The helper replaces the connection
when its token changes and stops providing it after sign-out. A saved
brickster handle can retain its old token, so obtain the connection from
`con()` each time. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#save-query-results)
for clearing saved results.

## Azure Databricks with Entra sign-in

For a workspace that accepts Microsoft Entra tokens, use an Entra Web
app registration with delegated Databricks access. Set
`OAUTHDB_TENANT_ID` and replace the client with:

``` r

client <- oauth_db_microsoft_client(
  services = "databricks_entra",
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
```

Change `host` to the Azure workspace hostname and set
`auth_mode = "entra"` on both
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md)
and
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).
