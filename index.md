# shinyOAuthDB

shinyOAuthDB helps you build Shiny apps that query a database or data
platform using each app user’s own account. People sign in with the
account they already use for that data source, and your app queries data
on their behalf.

This is useful when you or your organization already manage accounts and
data permissions in a database or data platform. Your Shiny app can
reuse those permissions, so you don’t have to maintain a separate set of
user accounts and data-access rules in the Shiny app. For example, if
your database limits an analyst to sales data for their region, your
Shiny dashboard can query the data as that analyst and automatically use
the same restriction.

The OAuth sign-in and data access work like this:

1.  A user navigates to your Shiny app. Your Shiny app shows a **Sign
    in** button. When the user clicks this button, the app uses
    shinyOAuth to start the OAuth sign-in flow. The user is sent to the
    sign-in page of the database or data platform, or to a trusted
    sign-in service (like your organization’s login service).
2.  The user signs in with their existing account and, if asked, approve
    the access your app requests.
3.  They return to your Shiny app and shinyOAuth obtains an **access
    token**, a temporary credential that lets your Shiny app request
    data on their behalf.
4.  Your Shiny app uses shinyOAuthDB to send that token with its data
    requests. The database or data platform checks the token and applies
    that user’s permissions before returning data.

shinyOAuthDB provides R functions to streamline the above steps, with
configurations for various databases and data platforms. It also helps
you open database connections, run queries, and make API calls.
Depending on the data source, you can work with familiar tools such as
DBI and dbplyr, or use the a supporting package’s query and API helpers.

Supported databases and data platforms (links open their setup guides):

[PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html)
·
[PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html)
· [DuckDB (over
Quack)](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.html)
· [Trino and
Starburst](https://lukakoning.github.io/shinyOAuthDB/articles/trino.html)
·
[Databricks](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.html)
· [Microsoft Fabric and
PowerBi](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html)
·
[Snowflake](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.html)
· [Google
BigQuery](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.html)
· [Amazon
Redshift](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html)
· [Azure SQL and SQL
Server](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html)
· [Azure
PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.html)
·
[ClickHouse](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.html)
·
[StarRocks](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.html)
· [libSQL and
Turso](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.html) ·
[CrateDB](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.html)
·
[OpenSearch](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.html).

Your database or data platform must accept OAuth access tokens, and
you’ll need to register your Shiny app with its sign-in service. Each
guide explains the setup and where to find the settings you need.

## Install

``` r

install.packages("remotes")
remotes::install_github("lukakoning/shinyOAuthDB")
```

## Example usage with PostgreSQL

Start [Docker](https://docs.docker.com/get-started/get-docker/) with
Linux containers, then run this app in R. The setup call starts
PostgreSQL, Keycloak sign-in and PostgREST, which lets R read PostgreSQL
over HTTP without installing a database driver. PostgreSQL applies each
user’s permissions.

Pass `auth$connection` to
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
then use `$select()` to read a table as the signed-in user.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

demo <- oauth_db_demo("postgrest", action = "services")

client <- oauth_client(
  demo$provider,
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

  postgres <- oauth_db_postgrest_api(
    auth$connection, url = demo$url
  )
  output$rows <- renderTable({
    postgres$select("visible_rows", order = "row_id.asc")
  })
}

shinyApp(ui, server, options = list(port = 18100), uiPattern = ".*",
         onStart = function() onStop(demo$stop))
```

Sign in as `alice` / `alice` or `bob` / `bob` (username / password). The
first build takes a few minutes; your browser may ask you to accept the
local sign-in certificate. Stopping the app removes its Docker services.
Call `demo$stop()` to stop the services manually.

The package includes this example as `examples/postgres/app.R`; [run it
directly](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html#run-the-minimal-example)
or edit a copy. For your own server, follow the [PostgREST
guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html).
For native PostgreSQL connections with DBI, see the [PostgreSQL
guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html).

## Try the demo

With [Docker](https://docs.docker.com/get-started/get-docker/) running
Linux containers, run the following in R. The first build takes several
minutes.

``` r

shinyOAuthDB::oauth_db_demo()
```

This starts PostgreSQL, Keycloak sign-in and a styled version of the
app. Open <http://localhost:18100> and sign in as `alice` / `alice` or
`bob` / `bob` (username / password). Each account sees only its own
rows. Your browser may ask you to accept the local test certificate.
Click **Stop demo** or interrupt R to remove the containers and sample
data.

See [Local Docker
demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html)
for other databases, editing the app in local R and troubleshooting.

For a cloud platform, `shinyOAuthDB::oauth_db_cloud_demo("fabric")`
guides you through sign-in setup and opens an editable local app. See
[Guided cloud
demos](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.html)
for the supported platforms and their setup requirements.

[Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html)
explains the Shiny pattern. [OAuth
setup](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html)
explains app registrations and sign-in settings. [Authentication and
sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.html)
covers multiple accounts, saved results and advanced permissions.
