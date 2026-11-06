# shinyOAuthDB

Query data from Shiny using each visitor's own account. shinyOAuthDB handles
database connections and API clients; [shinyOAuth](https://github.com/lukakoning/shinyOAuth)
handles sign-in and token renewal. The database enforces the visitor's
permissions, including which rows they can see.

Supported databases and platforms (links open their setup guides):

[PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html) ·
[PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html) ·
[Trino and Starburst Enterprise](https://lukakoning.github.io/shinyOAuthDB/articles/trino.html) ·
[StarRocks](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.html) ·
[DuckDB](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.html) ·
[libSQL and Turso](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.html) ·
[CrateDB](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.html) ·
[OpenSearch](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.html) ·
[ClickHouse](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.html) ·
[Microsoft Fabric](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html) ·
[Databricks](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.html) ·
[Snowflake](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.html) ·
[Google BigQuery](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.html) ·
[Azure SQL and SQL Server](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html) ·
[Azure PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.html) ·
[Amazon Redshift](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html).

Self-hosted servers need OAuth configured. Each guide explains how to prepare
the server, register the app and find the settings you need.

## Install

```r
install.packages("remotes")
remotes::install_github("lukakoning/shinyOAuthDB")
```

## Try PostgreSQL locally

Install and start [Docker](https://docs.docker.com/get-started/get-docker/)
with Linux containers. In R, run:

```r
shinyOAuthDB::oauth_db_demo()
```

This starts PostgreSQL 18, Keycloak sign-in and a Shiny app. The package
includes the configuration and sample data. The first build downloads its
dependencies and compiles PostgreSQL; allow several minutes.

Open <http://localhost:18100> once the app is ready. Sign in as `alice` with
password `alice-fixture-password`, or `bob` with `bob-fixture-password`.
Your browser may ask you to accept the local test certificate for Keycloak.
Each account sees its own rows from the same query.

Click **Stop demo**, or interrupt R, to remove the containers and demo data.
After a forced exit, use `oauth_db_demo(action = "stop")`.

## The Shiny app

This is the demo's `app.R`, which runs inside Docker with its database
driver and certificates. Sign-in gives `auth$connection` to the database
helper; `con()` gets that visitor's connection before each query.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

ui <- oauth_ui(fluidPage(
  h2("postgres demo"),
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows"),
  actionButton("stop", "Stop demo")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$stop, stopApp())

  con <- oauth_db_postgres(
    auth$connection, host = "localhost", dbname = "oauthdb_fixture",
    user = function() req(auth$token@userinfo$preferred_username),
    issuer = issuer, scope = "database.read",
    sslrootcert = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT marker FROM visible_rows ORDER BY row_id")
  })
}

shinyApp(ui, server, uiPattern = ".*")
```

To edit and rerun this app, or try the packaged PostgREST, Trino and StarRocks
setups, follow [Local Docker demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html).
For your own server, follow the [PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html).

[Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html) explains the Shiny pattern.
[OAuth setup](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html) explains app registrations and
sign-in settings. [Authentication and sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.html)
covers multiple accounts, saved results and advanced permissions.
