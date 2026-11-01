# shinyOAuthDB

Build Shiny apps that use each visitor's own access to Azure SQL, Microsoft
Fabric, BigQuery, Redshift, Databricks, Snowflake, Trino, or Azure PostgreSQL. Sign them in, then query
with DBI or use the platform's R functions. The database decides what each
person can access.

Choose your platform below. Each example is a complete `app.R`, including
the matching shinyOAuth sign-in configuration.

[BigQuery](#google-bigquery) · [Azure SQL and SQL Server](#azure-sql-and-sql-server) ·
[Fabric](#microsoft-fabric) · [Databricks](#databricks) ·
[Redshift](#amazon-redshift) · [Snowflake](#snowflake) · [Trino](#trino-and-starburst-enterprise) ·
[Azure PostgreSQL](#azure-postgresql)

## Google BigQuery

Use a Google Cloud Web OAuth registration and give users permission to run
query jobs in the billing project and read the data. This app queries BigQuery
directly through its REST API.

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

`bigquery$query()` returns a data frame and handles polling and result pages.
It also accepts named parameters, such as `parameters = list(country = "NL")`.
See [BigQuery guide](vignettes/bigquery.Rmd) for more.

## Azure SQL and SQL Server

Use an Entra registration with delegated SQL access. This app lists tables
the signed-in person can access.

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

## Microsoft Fabric

This app queries a Warehouse or Lakehouse SQL endpoint and lists the user's
Fabric workspaces. Use an Entra registration with delegated SQL and Fabric
workspace-read permissions.

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

The API client also works with fabricQueryR's resource objects and functions
for OneLake, DAX, KQL, and GraphQL. See the
[Fabric guide](vignettes/fabric.Rmd).

## Databricks

Register a Databricks OAuth application for your workspace. This app runs a
SQL query and lists warehouses through brickster.

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

Use a Snowflake OAuth integration and a role your users can access.
This app shows the signed-in user's Snowflake identity and role.

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

## Amazon Redshift

This example uses Microsoft Entra sign-in for a Redshift deployment linked
to IAM Identity Center. Set `OAUTHDB_REDSHIFT_RESOURCE` and
`OAUTHDB_REDSHIFT_SCOPE` to the resource and delegated scope of the Entra
registration trusted by that deployment.

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

Install the AWS Redshift ODBC 2.x driver and select its installed name with
the helper's `driver` argument if it differs from the default. Other identity
providers can use their own shinyOAuth client with the same connection helper.
See [Redshift guide](vignettes/redshift.Rmd).

## Trino and Starburst Enterprise

Use the cluster's OIDC provider and configure the cluster to accept tokens
issued for your app. This example maps the verified profile's email to the
Trino username; use the claim that matches your cluster's principal mapping.

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

Set `OAUTHDB_TRINO_ISSUER` to the provider's issuer URL and install `RTrino`.
Adjust scopes to your IdP registration. RTrino handles DBI queries while
shinyOAuthDB supplies a current token for each request.
See [Trino guide](vignettes/trino.Rmd).

## Azure PostgreSQL

Use an Entra registration for Azure PostgreSQL and a database role provisioned
for the user or their group. This app connects through RPostgres.

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

## Run an example

Register an OAuth application with your platform and use
`http://localhost:8100` as its redirect URI. The Microsoft examples use an
Entra Web app registration with delegated permissions for the chosen service.
Users also need access to the database or platform.

Put the registration's credentials in `OAUTHDB_CLIENT_ID` and
`OAUTHDB_CLIENT_SECRET`, for example in your local `.Renviron`. Microsoft
examples also use `OAUTHDB_TENANT_ID`. Restart R after editing `.Renviron`.

Replace the example connection settings, save the code as `app.R`, and run
`shiny::runApp(port = 8100)`. Open `http://localhost:8100` to sign in.
The [getting-started guide](vignettes/getting-started.Rmd) covers installation.

## Using the examples in your app

Create the sign-in client outside `server()`. Inside `server()`,
`oauth_module_server()` handles the visitor's sign-in, and a database helper
such as `oauth_db_azure_sql()` gives you a connection function.

Pass `auth$connection` without parentheses. Call `connection <- con()`
inside your render or reactive expression, then query with DBI or dbplyr.
The helper opens the connection on first use, reuses it, and closes it on
sign-out or session end. Outputs stay blank before sign-in.

API clients supply credentials to the R function passed to `$call()`.
Use its usual arguments and return value.

## Further reading

- [Getting started](vignettes/getting-started.Rmd): installation and a guide for each source.
- [Authentication and sessions](vignettes/authorization.Rmd): existing logins, permissions, multiple accounts, and stored results.

The [playground](playground/README.md) has runnable scripts and an offline
SQLite demo. [Development notes](docs/README.md) cover contributing and checks.
