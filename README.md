# shinyOAuthDB

'shinyOAuthDB' is an R package which helps you build Shiny apps that query data with each visitor's own account.
It is a bridge between Shiny and the database or platform's OAuth sign-in, 
with functions to easily retrieve a database connection or API client for the signed-in user.

The app user signs in with their own account, 
and your app can query the database or platform on their behalf.

For instance, if you have given someone permission to access a table in a data platform, 
like Databricks, Snowflake, or Microsoft Fabric, they can sign in with that same account.
Your Shiny app then has access to just the data they are already allowed to see in the data platform.
The advantage is that you don't need to manage a separate permission system for your app;
access is enforced by the platform's own permissions.

'shinyOAuthDB' supports multiple data platforms and databases, including:

[Microsoft Fabric](#microsoft-fabric) · [Databricks](#databricks) ·
[Snowflake](#snowflake) · [BigQuery](#google-bigquery) ·
[Azure SQL and SQL Server](#azure-sql-and-sql-server) ·
[PostgreSQL](#self-hosted-postgresql) · [Azure PostgreSQL](#azure-postgresql) ·
[Redshift](#amazon-redshift) · [Trino](#trino-and-starburst-enterprise) · [ClickHouse](#clickhouse) · [StarRocks](#starrocks) · [PostgREST](#postgrest)

## Microsoft Fabric

Query a Warehouse or Lakehouse SQL endpoint and list the user's Fabric
workspaces. The Entra Web app registration needs delegated SQL access and
the Fabric permissions `Workspace.Read.All` and `Item.Read.All`. The Fabric
preset requires both permissions, including when only listing workspaces.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = c("sql", "fabric"),
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)

ui <- oauth_ui(fluidPage(
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows"),
  verbatimTextOutput("workspaces")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_fabric_sql(
    auth$connection,
    server = "example.datawarehouse.fabric.microsoft.com",
    database = "Reporting"
  )
  fabric <- oauth_db_fabric_api(auth$connection)

  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT TOP (20) * FROM dbo.Orders")
  })
  output$workspaces <- renderPrint({
    fabric$call(fabricQueryR::fabric_workspaces)
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

Use the same API client with fabricQueryR functions for OneLake, DAX, KQL,
or GraphQL. The [Fabric guide](vignettes/fabric.Rmd) also shows how to use
Lakehouse and semantic model objects.

## Databricks

Query a SQL warehouse and list warehouses through brickster using the
visitor's Databricks account. Register a Databricks OAuth application
for the workspace first.

```r
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

ui <- oauth_ui(fluidPage(
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows"),
  verbatimTextOutput("warehouses")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_databricks(
    auth$connection,
    host = host,
    warehouse_id = "warehouse-id"
  )
  databricks <- oauth_db_databricks_api(auth$connection, host = host)

  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user()")
  })
  output$warehouses <- renderPrint({
    databricks$call(brickster::db_sql_warehouse_list)
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

For Azure Databricks with Entra sign-in, use the Microsoft client with
`services = "databricks_entra"` and set `auth_mode = "entra"` on both helpers.
See the [Databricks guide](vignettes/databricks.Rmd) for that client setup
and more brickster examples.

## Snowflake

Check the signed-in user's Snowflake username and role, then add your own
SQL. You'll need a Snowflake OAuth integration and a role your users can
access.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_snowflake_client(
  server = "organization-account.snowflakecomputing.com",
  role = "REPORTING_READER",
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

  con <- oauth_db_snowflake(
    auth$connection,
    server = "organization-account.snowflakecomputing.com",
    role = "REPORTING_READER",
    warehouse = "REPORTING_WH",
    database = "ANALYTICS"
  )

  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT CURRENT_USER(), CURRENT_ROLE()")
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

For External OAuth through Entra, Okta, or another provider, see the
[Snowflake guide](vignettes/snowflake.Rmd).

## Google BigQuery

Query BigQuery with a user's Google account and display the result as a data
frame. Create a Google Cloud Web OAuth registration; users need permission
to run query jobs in the billing project and read the data.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_bigquery_client(
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

  bigquery <- oauth_db_bigquery_api(
    auth$connection,
    project = "billing-project",
    location = "EU"
  )
  output$rows <- renderTable({
    bigquery$query("SELECT * FROM reporting.Orders LIMIT 20")
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

`bigquery$query()` returns a data frame. Pass named values in `parameters`
for queries that use parameters such as `@country`. See the
[BigQuery guide](vignettes/bigquery.Rmd) for examples.

## Azure SQL and SQL Server

List the database tables a user can access after Microsoft sign-in.
Use an Entra Web app registration with permission to access SQL on the
user's behalf.

```r
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

ui <- oauth_ui(fluidPage(
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_azure_sql(
    auth$connection,
    server = "example.database.windows.net",
    database = "Reporting"
  )

  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT TOP (20) name FROM sys.tables")
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

For SQL Server configured for Entra authentication, use
`oauth_db_sql_server()` with your server and database. The rest of the app
stays the same. See the [Azure SQL guide](vignettes/azure-sql.Rmd) for dbplyr
and connection options.

## Self-hosted PostgreSQL

Query your own PostgreSQL 18 server with an OAuth provider such as Keycloak.
PostgreSQL validates each visitor's token and database role, then applies
table grants and row-level security.

```r
# Inside server(), using a shinyOAuth client for your identity provider:
con <- oauth_db_postgres(
  auth$connection,
  host = "postgres.example.org", dbname = "reporting", user = "alice",
  issuer = "https://login.example.org/realms/reporting",
  scope = "database.read", sslrootcert = "path/to/ca.pem"
)
output$rows <- shiny::renderTable({
  DBI::dbGetQuery(con(), "SELECT current_user")
})
```

Native OAuth currently needs Linux with a shared libpq 18 build. On Windows
or macOS, try the [Docker playground](playground/postgres/README.md): run
`source("playground/postgres/run.R")` from the checkout root to launch
PostgreSQL, Keycloak and a Shiny app with sample data. The
[PostgreSQL guide](vignettes/postgres.Rmd) covers server configuration,
browser sign-in and role mapping. A separate GitHub Actions workflow runs
the real browser and database tests.

## Azure PostgreSQL

Query Azure PostgreSQL through RPostgres using a Microsoft account.
Use an Entra registration for PostgreSQL access and a database role
created for the user or their group.

```r
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

ui <- oauth_ui(fluidPage(
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows")
), id = "auth", client = client)

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

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

The [Azure PostgreSQL guide](vignettes/azure-postgres.Rmd) covers database
roles and connection settings.

## Amazon Redshift

Query Redshift through an IAM Identity Center deployment using Microsoft
Entra sign-in. Ask the administrator for the OAuth resource and delegated
scope, and set them in `OAUTHDB_REDSHIFT_RESOURCE` and
`OAUTHDB_REDSHIFT_SCOPE`.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  token_targets = list(redshift = list(
    resource = Sys.getenv("OAUTHDB_REDSHIFT_RESOURCE"),
    scopes = Sys.getenv("OAUTHDB_REDSHIFT_SCOPE")
  ))
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

  con <- oauth_db_redshift(
    auth$connection,
    server = "cluster.example.eu-west-1.redshift.amazonaws.com",
    database = "reporting",
    target = "redshift"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user AS database_user")
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

Install the AWS Redshift ODBC 2.x driver with `IdpTokenAuthPlugin` support.
Set `driver` if its installed name differs from the default. The
[Redshift guide](vignettes/redshift.Rmd) covers other sign-in providers
and token types.

## Trino and Starburst Enterprise

Query Trino with DBI after signing in through the cluster's identity
provider. The cluster must accept your app's tokens. This example uses
the profile's email as the Trino username; use the field your cluster
expects.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_TRINO_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "email", "offline_access")
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

  con <- oauth_db_trino(
    auth$connection,
    host = "https://trino.example.org",
    catalog = "lakehouse",
    schema = "reporting",
    user = function() req(auth$token@userinfo$email)
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT * FROM Orders LIMIT 20")
  })
}

shinyApp(ui, server, options = list(port = 8100), uiPattern = ".*")
```

Install `RTrino` and set `OAUTHDB_TRINO_ISSUER` to the provider's issuer URL.
Use the scopes allowed by the registration. See the
[Trino guide](vignettes/trino.Rmd) for setup and connection options.

## PostgREST

Read PostgreSQL tables and views through PostgREST with each visitor's JWT.
The API validates the token and PostgreSQL applies grants and row-level
security. Create `oauth_db_postgrest_api(auth$connection, url = ...)`
inside `server()`, then call `$select()` or `$rpc()` in reactive code.
The [PostgREST guide](vignettes/postgrest.Rmd) has server setup, a complete
Shiny app, filters, and pagination examples.

## StarRocks

Query StarRocks 3.5 or later through its JWT authentication plugin and
MySQL Connector/ODBC. Create `oauth_db_starrocks(auth$connection, ...)`
inside `server()` and query the returned connection with DBI or dbplyr.
The [StarRocks guide](vignettes/starrocks.Rmd) covers the driver, trusted
issuer and audience, TLS, database roles, and a complete Shiny app.

## ClickHouse

Query a JWT-enabled ClickHouse endpoint through its HTTPS interface.
Create `oauth_db_clickhouse_api(auth$connection, url = ...)` inside
`server()` and call `$query()` for a data frame with named SQL parameters.
Custom identity providers currently require ClickHouse Cloud Enterprise.
The [ClickHouse guide](vignettes/clickhouse.Rmd) covers sign-in, endpoint
configuration, result types, and a complete Shiny app.

## Run an example

Register an OAuth application with your platform and use
`http://localhost:8100` as its redirect URI. The Microsoft examples use an
Entra Web app registration with delegated permissions for the chosen service.
Users also need access to the database or platform.

Save the client ID and secret in `OAUTHDB_CLIENT_ID` and
`OAUTHDB_CLIENT_SECRET`, for example in a local `.Renviron` file.
Microsoft examples also need `OAUTHDB_TENANT_ID`.
Restart R after editing `.Renviron`.

Replace the example connection settings, save the code as `app.R`, and run
`shiny::runApp(port = 8100)`. Open `http://localhost:8100` to sign in.
The [getting-started guide](vignettes/getting-started.Rmd) covers installation.

## Using the examples in your app

Create the sign-in client outside `server()`. Inside `server()`,
`oauth_module_server()` handles the visitor's sign-in, and a database helper
such as `oauth_db_azure_sql()` gives you a connection function.

Pass `auth$connection` without parentheses. Call `connection <- con()`
inside your render or reactive expression, then query with DBI or dbplyr.
The helper opens the connection on first use and reuses it. On sign-out or
session end, it stops returning the connection and calls the driver's
cleanup method. A retained Databricks connection can still use its copied
token, so call `con()` before each operation. Outputs stay blank before sign-in.

Fabric and Databricks API clients pass credentials to the function supplied
to `$call()`. Use the function's usual arguments and return value.
BigQuery provides query methods such as `$query()`.

## Further reading

- [Getting started](vignettes/getting-started.Rmd): installation and a guide for each source.
- [Authentication and sessions](vignettes/authorization.Rmd): existing logins, permissions, multiple accounts, and stored results.

The [playground](playground/README.md) has runnable scripts and an offline
SQLite demo. [Development notes](docs/README.md) cover contributing and checks.
