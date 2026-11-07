# shinyOAuthDB

shinyOAuthDB helps you build Shiny apps that query a database or data
platform using each app user's own account. People sign in with the account
they already use for that data source, and your app queries data on their
behalf.

This is useful when you or your organization already manage accounts and data
permissions in a database or data platform. Your Shiny app can reuse those permissions, 
so you don't have to maintain a separate set of user accounts and data-access rules in the Shiny app. 
For example, if your database limits an analyst to sales data for their region, 
your Shiny dashboard can query the data as that analyst and automatically use the same restriction.

The OAuth sign-in and data access work like this:

1. A user navigates to your Shiny app. Your Shiny app shows a **Sign in** button. 
   When the user clicks this button, the app uses shinyOAuth to start the OAuth sign-in flow. 
   The user is sent to the sign-in page of the database or data platform, 
   or to a trusted sign-in service (like your organization's login service).
2. The user signs in with their existing account and, if asked, approve the
   access your app requests.
3. They return to your Shiny app and shinyOAuth obtains an **access token**, 
   a temporary credential that lets your Shiny app request data on their behalf.
4. Your Shiny app uses shinyOAuthDB to send that token with its data requests.
   The database or data platform checks the token and applies that user's
   permissions before returning data.

shinyOAuthDB provides R functions to streamline the above steps,
with configurations for various databases and data platforms.
It also helps you open database connections, run queries, and make API calls.
Depending on the data source, you can work with familiar tools such as DBI and dbplyr,
or use the a supporting package's query and API helpers.

Supported databases and data platforms (links open their setup guides):

[PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html) ·
[PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html) ·
[DuckDB (over Quack)](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.html) ·
[Trino and Starburst](https://lukakoning.github.io/shinyOAuthDB/articles/trino.html) ·
[Databricks](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.html) ·
[Microsoft Fabric and PowerBi](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html) ·
[Snowflake](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.html) ·
[Google BigQuery](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.html) ·
[Amazon Redshift](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html) ·
[Azure SQL and SQL Server](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html) ·
[Azure PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.html) ·
[ClickHouse](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.html) ·
[StarRocks](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.html) ·
[libSQL and Turso](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.html) ·
[CrateDB](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.html) ·
[OpenSearch](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.html).

Your database or data platform must accept OAuth access tokens, and you'll
need to register your Shiny app with its sign-in service. Each guide explains
the setup and where to find the settings you need.

## Install

```r
install.packages("remotes")
remotes::install_github("lukakoning/shinyOAuthDB")
```

## Example usage with PostgreSQL

A demo app is included to show the sign-in and query code. 
It runs PostgreSQL inside a Docker container, with Keycloak for sign-in. 
The demo uses a small dataset and a simple query to show how each signed-in user sees only their own rows.

Install and start [Docker](https://docs.docker.com/get-started/get-docker/).
In R, run:

```r
shinyOAuthDB::oauth_db_demo()
```

Then, open the Shiny app at <http://localhost:18100>.
Sign in as `alice` with password `alice`, or as `bob` with password `bob`.
(Your browser may ask you to accept the local test certificate for Keycloak.)

### Shiny app code

This minimal app shows the sign-in and query code. 

It passes `auth$connection` to `oauth_db_postgres()`, then calls `con()` before querying. 
The PostgreSQL database applies the signed-in user's permissions.

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
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

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

The package includes this small example as `examples/postgres/app.R`.
See [Run the minimal example](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html#run-the-minimal-example)
to run it with the same Docker services.

To edit the styled demo, or try the packaged DuckDB Quack, Trino, PostgREST,
StarRocks, libSQL, CrateDB and OpenSearch setups, follow
[Local Docker demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html).
For editing in local R, `shinyOAuthDB::oauth_db_demo("postgrest", app = "local")` runs
PostgreSQL, PostgREST and sign-in in Docker while you edit and run the Shiny app on
your computer. The [local app guide](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html#run-and-edit-shiny-in-local-r)
explains the R packages and drivers needed for each database.
For your own server, follow the [PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html).

For a cloud platform, `shinyOAuthDB::oauth_db_cloud_demo("fabric")` guides you
through sign-in setup and opens an editable local app. The guide also supports
Databricks, Snowflake, BigQuery, Redshift, Azure SQL, Azure PostgreSQL and
ClickHouse Cloud. See
[Guided cloud demos](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.html)
for each platform's settings, app registration and service requirements.

[Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html) explains the Shiny pattern.
[OAuth setup](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html) explains app registrations and
sign-in settings. [Authentication and sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.html)
covers multiple accounts, saved results and advanced permissions.
