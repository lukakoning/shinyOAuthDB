# shinyOAuthDB

shinyOAuthDB helps you build Shiny apps that query a database or data
platform using each app user's own account. People sign in with the account
they already use for that data source, and your app queries data on their
behalf.

This is useful when your organization already manages accounts and data
permissions in a database or data platform. Your Shiny app can reuse those
permissions, so you don't have to maintain a separate set of user accounts
and data-access rules in the app. For example, if your database limits an
analyst to sales data for their region, a Shiny dashboard can query as that
analyst and use the same restriction.

The OAuth sign-in and data access work like this:

1. A user clicks **Sign in** in your Shiny app.
   [shinyOAuth](https://github.com/lukakoning/shinyOAuth) sends their browser
   to the platform's sign-in page, or to a sign-in service that your database
   trusts, such as your organization's login service.
2. They sign in with their existing account and, if asked, approve the
   access your app requests.
3. They return to your Shiny app. shinyOAuth obtains an **access token**,
   a temporary credential that lets the app request data on their behalf.
4. Your app uses shinyOAuthDB to send that token with its data requests.
   The database or platform checks the token and applies that user's
   permissions before returning data.

shinyOAuthDB provides R functions to open database connections, run queries
and make API calls. Depending on the data source, you can work with familiar
tools such as DBI and dbplyr, or use the package's query and API helpers.
shinyOAuth handles sign-in and token renewal.

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

Your database or data platform must accept OAuth access tokens, and you'll
need to register your Shiny app with its sign-in service. Each guide explains
the setup and where to find the settings you need.

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
library(bslib)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

example_query <- "SELECT marker FROM visible_rows ORDER BY row_id"

ui <- oauth_ui(page_sidebar(
  title = h2("PostgreSQL OAuth demo", class = "h3 mb-0"),
  theme = bs_theme(version = 5, primary = "#17646c", bg = "#f4f6f9", fg = "#23313d", base_font = "system-ui"), fillable = FALSE, lang = "en",
  sidebar = sidebar(width = 320, bg = "#fff", fg = "#23313d", open = list(desktop = "always", mobile = "always-above"),
    h3("1. Sign in", class = "h5"),
    p("Choose a demo account. Sign out before trying the other one."),
    tags$dl(class = "demo-details",
      tags$dt("alice"), tags$dd(code("alice-fixture-password")),
      tags$dt("bob"), tags$dd(code("bob-fixture-password"))
    ),
    div(class = "d-flex gap-2 flex-wrap",
      actionButton("login", "Sign in", class = "btn-primary"),
      actionButton("logout", "Sign out")),
    div(role = "status", textOutput("account"), textOutput("sign_in_status")),
    p("Sign-in opens Keycloak. Your browser may ask you to allow its local test certificate.", class = "demo-note"),
    hr(),
    p(a("Set up your own PostgreSQL data source", href = "https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html")),
    actionButton("stop", "Stop demo"),
    p("Stopping removes the demo services and sample data. Your copied app code is kept.", class = "demo-note")
  ),
  tags$style(".demo-details { display: grid; grid-template-columns: minmax(7rem, 1fr) minmax(0, 3fr); gap: .6rem 1rem; }
    .demo-details dt { font-size: .9rem; color: #485867; }
    .demo-details dd { margin: 0; overflow-wrap: anywhere; }
    .sidebar .demo-details { grid-template-columns: 1fr; gap: .25rem; }
    .sidebar .demo-details dd { margin-bottom: .5rem; }
    @media (max-width: 575px) { .main .demo-details { grid-template-columns: 1fr; gap: .25rem; } .main .demo-details dd { margin-bottom: .6rem; } }
    .demo-details code { color: inherit; white-space: normal; overflow-wrap: anywhere; }
    .demo-results { overflow-x: auto; }
    .demo-note { color: #485867; font-size: .95rem; }
    .btn { min-height: 44px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    .card-header h3 { font-size: 1.1rem; margin: 0; }
    .card, .sidebar { background: #fff; }
    .bslib-card { margin-top: 1rem; }
    .card-body > p { margin-bottom: 0; }"),
  p("Query PostgreSQL with the account of the person who signs in.", class = "lead"),
  card(fill = FALSE,
    card_header(h3("2. Query sample data")),
    pre(example_query),
    p("Sign in as alice, then sign out and try bob. The same request returns different rows because the data source applies their permissions."),
    conditionalPanel("!output.account", p("Sign in to load the sample data.", class = "demo-note")),
    div(class = "demo-results", tableOutput("rows"))
  ),
  card(fill = FALSE,
    card_header(h3("About this connection")),
    tags$dl(class = "demo-details",
      tags$dt("Database"), tags$dd(code("oauthdb_fixture")),
      tags$dt("Server"), tags$dd(code("localhost:5432")),
      tags$dt("Table"), tags$dd(code("visible_rows")),
      tags$dt("Connection"), tags$dd(code("DBI / RPostgres with native PostgreSQL OAuth"))
    ),
    p("PostgreSQL checks the OAuth token, maps the person to a database role and applies row-level security."),
    p("The database connection verifies its server certificate using this demo's local test CA.", class = "demo-note")
  )
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$stop, stopApp())

  output$sign_in_status <- renderText({
    if (!is.null(auth$error) && !auth$error %in% c("logged_out", "access_denied")) {
      return("Sign-in didn't finish. Check the local test certificate in your browser, then try Sign in again.")
    }
    reference <- tryCatch(auth$connection(), error = function(error) NULL)
    if (is.null(reference)) "Not signed in. Choose one of the demo accounts above." else "Sign out before trying the other account."
  })
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })

  con <- oauth_db_postgres(
    auth$connection, host = "localhost", dbname = "oauthdb_fixture",
    user = function() req(auth$token@userinfo$preferred_username),
    issuer = issuer, scope = "database.read",
    sslrootcert = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, example_query)
  })
}

shinyApp(ui, server, uiPattern = ".*")
```

To edit and rerun this app, or try the packaged PostgREST, Trino, StarRocks,
DuckDB Quack, libSQL, CrateDB and OpenSearch setups, follow
[Local Docker demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html).
For editing in local R, `shinyOAuthDB::oauth_db_demo("postgrest", app = "local")` runs
PostgreSQL, PostgREST and sign-in in Docker while you edit and run the Shiny app on
your computer. The [local app guide](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html#run-and-edit-shiny-in-local-r)
explains the R packages and drivers needed for each database.
For your own server, follow the [PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html).

For a cloud platform, `shinyOAuthDB::oauth_db_cloud_demo("fabric")` guides you
through sign-in setup and opens an editable local app. The guide also supports
Databricks, BigQuery, Snowflake, Azure SQL, Azure PostgreSQL, Redshift and
ClickHouse Cloud. See
[Guided cloud demos](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.html)
for each platform's settings, app registration and service requirements.

[Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html) explains the Shiny pattern.
[OAuth setup](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html) explains app registrations and
sign-in settings. [Authentication and sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.html)
covers multiple accounts, saved results and advanced permissions.
