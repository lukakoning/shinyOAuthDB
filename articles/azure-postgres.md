# Azure PostgreSQL

Azure Database for PostgreSQL hosts the open-source PostgreSQL database
for you. Connect a Shiny app to Azure Database for PostgreSQL using each
visitor’s Microsoft account. Queries use RPostgres connections, so you
can keep your usual DBI or dbplyr code.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("azure-postgres")` in your R
console. The guide asks for `server`, `database`, mapped database `user`
role, `sslrootcert` (a local trusted CA bundle), Entra `tenant_id` and
`client_id`. It explains the difference between registering the Shiny
app and creating the Entra database principal. A group role still
requires each visitor’s own sign-in and valid group membership.

Install `RPostgres`, `processx` and `askpass` first. The local editable
app opens a verified TLS connection only after **Run example query**.
Its first query reports the database role and database name, so no table
is needed. For scripts, supply those settings with `prompt = FALSE`;
`database_port` defaults to 5432. A confidential app uses masked input
or `OAUTHDB_AZURE_POSTGRES_CLIENT_SECRET`. See [Guided cloud
demos](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.md)
for draft setup and editing.

With no Azure server yet, start with the [service
overview](https://learn.microsoft.com/en-us/azure/postgresql/overview).
Arrange Entra authentication, role grants and network access before
trying the query. The demo doesn’t provision or stop a cloud server.

## Set up access

In R, run `install.packages("RPostgres")`. Ask your administrator to
[enable Entra authentication and create database
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
steps](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html#register-a-microsoft-entra-app)
and configure delegated access to **Azure OSSRDBMS Database**. The
preset requests `https://ossrdbms-aad.database.windows.net/.default`.

| Value in the app | Where to find it |
|----|----|
| `host` | Azure PostgreSQL server overview, full server name ending in `.postgres.database.azure.com` |
| `dbname` | The database name in your existing connection settings |
| `user` | The Entra user or group role created in PostgreSQL by the Entra administrator |
| `sslrootcert` | The CA bundle recommended for your server’s certificate chain |
| Tenant ID, client ID, secret | [Entra registration](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html#register-a-microsoft-entra-app) |

Allow the app host through the server’s networking settings too.

## A complete app

Save this as `example.R`. Replace the host, database, and role name, and
set `sslrootcert` to your CA bundle’s path:

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
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_azure_postgres(
    auth$connection,
    host = "example.postgres.database.azure.com",
    dbname = "reporting",
    user = "reporting-readers",
    sslrootcert = "path/to/root-ca.pem"
  )

  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user")
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

## Read a table

The first query shows the PostgreSQL role. To read your data, replace
that output expression with a query for your table:

``` r

output$rows <- renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT * FROM reporting.orders LIMIT 20")
})
```

Call `con()` inside the reactive expression before querying. You can
also pass the resulting `connection` to
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) for
dbplyr queries. Use DBI parameter binding for SQL values entered by
users.

## Roles and connection settings

The example connects as a group role, `reporting-readers`. Each person
still signs in with their own account; PostgreSQL checks that they
belong to the group. Use the role your administrator has created for
your users.

You can omit `sslrootcert` if libpq already has the correct CA bundle
configured. Other options, such as `port` and `connect_timeout`, go to
RPostgres. See
[`?oauth_db_azure_postgres`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md)
for the connection arguments.

For custom sign-in settings or saved query results, see [Authentication
and
sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.md).
