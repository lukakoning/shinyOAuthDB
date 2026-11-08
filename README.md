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

1. A user navigates to your Shiny app. Your Shiny app shows a **Sign in** button
   (shinyOAuth can also redirect users to the provider automatically).
   When the user clicks this button, the app uses shinyOAuth to start the OAuth sign-in flow.
   The user is sent to the sign-in page of the database or data platform,
   or to a trusted sign-in service (like your organization's login service).
2. The user signs in with their existing account and, if asked, approves the
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
or use a supporting package's query and API helpers.

Supported databases and data platforms (links open their setup guides):

[PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html) ·
[PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html) ·
[DuckDB (over Quack)](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.html) ·
[Trino and Starburst](https://lukakoning.github.io/shinyOAuthDB/articles/trino.html) ·
[Databricks](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.html) ·
[Microsoft Fabric and Power BI](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html) ·
[Snowflake](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.html) ·
[Google BigQuery](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.html) ·
[Amazon Redshift](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html) ·
[Azure SQL and SQL Server](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html) ·
[Azure PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.html) ·
[SAP HANA and HANA Cloud](https://lukakoning.github.io/shinyOAuthDB/articles/hana.html) ·
[Supabase](https://lukakoning.github.io/shinyOAuthDB/articles/supabase.html) ·
[Oracle Database](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.html) ·
[Oracle REST Data Services](https://lukakoning.github.io/shinyOAuthDB/articles/oracle-ords.html) ·
[ClickHouse](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.html) ·
[StarRocks](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.html) ·
[libSQL and Turso](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.html) ·
[CrateDB](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.html) ·
[OpenSearch](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.html) ·
[Salesforce CRM and Data Cloud](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.html).

## Install

```r
if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes")
}
remotes::install_github("lukakoning/shinyOAuthDB")
```

## Example usage with PostgreSQL

Below is a minimal example of a Shiny app that queries a PostgreSQL database.

It launches PostgreSQL and Keycloak sign-in in Docker
(so install and launch [Docker](https://docs.docker.com/engine/install/) if you wish to run it).

This example uses PostgREST since it does not require a database driver to be installed, but you could also use DBI with a PostgreSQL driver.
See the [PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html) for that.

```r
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

# Start a local demo with PostgreSQL and Keycloak sign-in in Docker
demo <- oauth_db_demo("postgrest", action = "services")

# Create an OAuth client for the demo Keycloak server
client <- oauth_client(
  demo$provider,
  client_id = "shiny-db",
  client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
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

  postgres <- oauth_db_postgrest_api(
    auth$connection,
    url = demo$url
  )
  output$rows <- renderTable({
    postgres$select("visible_rows", order = "row_id.asc")
  })
}

runApp(
  shinyApp(
    ui, server, 
    uiPattern = ".*", 
    onStart = function() { onStop(demo$stop) }
  ),
  port = 18100,
  launch.browser = FALSE
)

# Open the app in your regular browser at http://localhost:18100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
```

Sign in as `alice` / `alice` or `bob` / `bob` (username / password).
The first build takes a few minutes; your browser may ask you to accept the
local sign-in certificate. Stopping the app removes its Docker services.

For your own PostgreSQL server, follow the [PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html)
or [PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html) guides.
For other databases and data platforms, refer to the links above.

## Learn more

[Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html)
walks through this app, explains OAuth settings, and covers connections,
sessions and saved results. Use the source guides above for the setup and
query methods specific to your database or data platform.

### More demos

The package includes various demo apps.

`oauth_db_demo()` runs local Docker demos for PostgreSQL and other self-hosted databases.
`oauth_db_cloud_demo()` guides demos for several cloud platforms, during which
you will be walked through first setup with your existing platform workspace and account.

See [Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app),
`?oauth_db_demo` and `?oauth_db_cloud_demo` for the demo options.


