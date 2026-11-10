# Azure PostgreSQL

Azure Database for PostgreSQL hosts a PostgreSQL database for you. With
shinyOAuthDB, people sign in to your Shiny app with their Microsoft
account and query data using the permissions already assigned to them in
PostgreSQL.

The database maps their Microsoft identity to a database role: a user or
group with permission to read particular data.
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md)
opens an RPostgres connection for that role, which you can use with DBI
or dbplyr.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("azure-postgres")` in the R
console for an editable app that walks through setup. In addition to
RPostgres, install `bslib`, `processx` and `askpass` for the local app.

The launcher asks for your Azure server, database role and sign-in
settings. After signing in, click **Run example query** to see the
connected database and role. It uses your existing Azure server;
stopping the app leaves that server running. See
[`?oauth_db_cloud_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
for optional settings and [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app)
for editing and resuming demos.

## Set up access

Ask your administrator to [enable Entra authentication and create
database
roles](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure)
for the app’s users or their groups. You’ll need the server and database
names, the database role to connect as, and a certificate bundle for the
server.

Create an Entra Web app registration for PostgreSQL access and register
`http://localhost:8100` as its redirect URI. Save these values in a
local `.Renviron` file and restart R:

``` text
OAUTHDB_TENANT_ID=your-tenant-id
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

Use the [Microsoft registration
steps](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html#register-a-microsoft-entra-app)
and configure delegated access to **Azure OSSRDBMS Database**. The
client preset requests the appropriate PostgreSQL permissions; see
[`?oauth_db_microsoft_client`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
when combining it with other services.

| Value in the app | Where to find it |
|----|----|
| `host` | Azure PostgreSQL server overview, full server name ending in `.postgres.database.azure.com` |
| `dbname` | The database name in your existing connection settings |
| `user` | The Entra user or group role created in PostgreSQL by the Entra administrator |
| `sslrootcert` | The CA bundle recommended for your server’s certificate chain |
| Tenant ID, client ID, secret | [Entra registration](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html#register-a-microsoft-entra-app) |

Allow the app host through the server’s networking settings too.

## A complete app

Save this as `example.R`. Replace the host, database, and role name, and
set `sslrootcert` to your CA bundle’s path:

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = "postgres",
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

  con <- oauth_db_azure_postgres(
    auth$connection,
    host = "example.postgres.database.azure.com",
    dbname = "reporting",
    user = "reporting-readers",
    sslrootcert = "path/to/root-ca.pem"
  )

  query_task <- oauth_db_task(con)

  observeEvent(input$load, {
    query_task$invoke("SELECT current_user")
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

## Read a table

The first query shows the PostgreSQL role. To read your data, replace
that output expression with a query for your table:

``` r

fetch_rows <- function(connection) {
  DBI::dbGetQuery(connection, "SELECT * FROM reporting.orders LIMIT 20")
}

query_task <- oauth_db_task(con, method = fetch_rows)

observeEvent(input$load, query_task$invoke())

output$rows <- renderTable(query_task$result())
```

Inside the worker function, you can also pass `connection` to
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) for
dbplyr queries. Use DBI parameter binding for SQL values entered by
users.

## Create the database identity

In Azure PostgreSQL’s **Authentication** settings, enable Entra and set
an Entra administrator. That administrator creates the database
principals for the people or groups who will use the app. Azure provides
`pgaadauth_create_principal` for this; its [Entra setup
guide](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure)
shows the supported commands and group mapping. Grant the resulting role
database/schema access and SELECT on the intended tables.

Use that exact database role as `user` in the app. The example’s shared
group role assumes the server maps signed-in members to that group. With
individual roles, choose a role for the current identity and have the
server verify the mapping; don’t let arbitrary input choose another
role.

## Roles and connection settings

You can omit `sslrootcert` if libpq already has the correct CA bundle
configured. Other options, such as `port` and `connect_timeout`, go to
RPostgres. See
[`?oauth_db_azure_postgres`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md)
for the connection arguments.

Use RPostgres linked to libpq 16 or later. The helper requires the
server to request the visitor’s access token as its password over
verified TLS; Kerberos, certificate-only and trust authentication cannot
replace it. Authentication and TLS settings cannot be changed through
`...`.

The next `con()` call after token renewal replaces the connection, so a
lost database session can reconnect with the current token. Complete a
transaction using the connection that started it. Token renewal does not
rerun a completed reactive query.

For custom sign-in settings or saved query results, see [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions).
