# Azure MySQL

Use
[`oauth_db_azure_mysql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_mysql.md)
to query Azure Database for MySQL Flexible Server with each Shiny
visitor’s Microsoft account. MySQL checks their Entra identity and
applies the privileges assigned to that user or group. The helper
returns a DBI connection for SQL and dbplyr queries.

## Set up access

Install the R package `odbc` and the 64-bit [MariaDB Connector/ODBC
driver](https://mariadb.com/docs/connectors/mariadb-connector-odbc/mariadb-connector-odbc-guide)
on the machine running Shiny. Use Connector/ODBC 3.1 or later. Find its
registered name with `unique(odbc::odbcListDrivers()$name)`; driver
names vary by installed version and operating system.

Ask your administrator to [enable Entra
authentication](https://learn.microsoft.com/en-us/azure/mysql/security/security-how-to-entra)
on the Flexible Server, configure an Entra administrator, and create
MySQL users for the visitors or their groups. Grant those users access
to your database and tables. The Shiny host also needs network access to
the server.

Create an Entra **Web** app registration with `http://localhost:8100` as
its redirect URI. Follow the [Microsoft registration
steps](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html#register-a-microsoft-entra-app),
but select **Azure OSSRDBMS Database** and its delegated
`user_impersonation` permission. Request admin consent if your tenant
requires it. Save the registration settings in a local `.Renviron` and
restart R:

``` text
OAUTHDB_TENANT_ID=your-tenant-id
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

Get the PEM CA bundle recommended in Azure’s [TLS configuration
guide](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/security-tls).
The driver verifies the certificate chain and server hostname. Keep the
bundle current as Azure rotates its certificates.

## A complete app

Save this as `example.R`. Replace the server, database, MySQL user or
group, driver name and CA bundle path with your settings:

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = "mysql",
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

  con <- oauth_db_azure_mysql(
    auth$connection,
    server = "example.mysql.database.azure.com",
    database = "reporting",
    user = "reporting-readers",
    driver = "MariaDB ODBC 3.2 Driver",
    ssl_ca = "path/to/azure-ca.pem"
  )

  query_task <- oauth_db_task(con)

  observeEvent(input$load, {
    query_task$invoke(
      "SELECT CURRENT_USER() AS database_user, DATABASE() AS database_name"
    )
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

Run `source("example.R")`, then open `http://localhost:8100` in your
regular browser. Embedded RStudio/Positron viewers can’t complete the
redirects. Sign in to see the MySQL identity and database; sign out to
clear the output.

For a group account, set `user` to the exact group name provisioned in
MySQL. Azure checks that the signed-in visitor belongs to that group.
For individual accounts, supply a reactive function returning the
provisioned MySQL name for the current identity. Don’t assume every
tenant maps an email address to the same database name.

## Query your tables

Pass `con` to
[`oauth_db_task()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_task.md)
to open a worker connection for DBI. For values supplied by users, use
bound parameters. Inside `server()`, replace the complete block from
`query_task <- oauth_db_task(con)` through
`output$rows <- renderTable(query_task$result())`, including the **Load
rows** observer, with:

``` r

fetch_rows <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT id, total FROM orders WHERE country = ? LIMIT 20",
    params = list("NL")
  )
}

query_task <- oauth_db_task(con, method = fetch_rows)

observeEvent(input$load, query_task$invoke())

output$rows <- renderTable(query_task$result())
```

You can also pass `connection` to
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) for
dbplyr queries. MySQL database grants determine what the visitor can
access. A group login uses that group’s grants; it doesn’t provide
individual row filtering on its own.

## Tokens and connections

The preset requests `https://ossrdbms-aad.database.windows.net/.default`
when MySQL is the only service, and the explicit `user_impersonation`
scope when combined with other Microsoft services. MySQL and Azure
PostgreSQL share this resource audience, with separate named token
targets `mysql` and `postgres`. An existing client can supply the same
audience through a custom `target`; use `target = NULL` for a client
without named targets.

The helper passes the access token as the password through
`mysql_clear_password` over verified TLS. You don’t need an OpenID
Connect driver plugin or a process-wide environment variable. MySQL
Enterprise’s ID-token authentication is a different mechanism.

This helper uses MariaDB’s driver to connect to Azure’s MySQL server.
MySQL Connector/ODBC 9.5 crashed during validation with credentials
longer than its connection-option buffer. MariaDB Connector/ODBC
accepted the 12 KB test token; the two drivers’ TLS settings are not
interchangeable.

After shinyOAuth renews a token, the next call to `con()` opens a
connection with the current token and closes the previous handle. This
doesn’t rerun completed reactive queries, but it ends any transaction or
temporary tables on the old connection. Obtain one handle for each
operation and complete its transaction before returning control to
Shiny.

The helper disables the driver’s automatic reconnect. If a query loses
its connection, handle the failure, disconnect the broken native handle,
and call `con()` before another query. It never automatically resubmits
SQL. Sign-out, account or username changes, and session end close the
connection.

## Validation

Unit tests cover driver arguments, token renewal, account changes and
permission loss. Local protocol checks can test the real ODBC driver’s
cleartext authentication over TLS. They don’t establish Azure
compatibility: before deployment, verify Entra consent, user/group
mapping and denied access with two real Azure users.
