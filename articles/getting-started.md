# Getting started

shinyOAuthDB helps you build Shiny apps that query a database or data
platform using each app user’s own account. People sign in with the
account they already use for that data source, and your app queries data
on their behalf.

This is useful when your organization already manages data permissions
in the database. For example, if an analyst can only read sales for
their region, your Shiny app can use the same restriction. You keep
those access rules in the database rather than maintaining another set
in the app.

## How sign-in and data access work

shinyOAuthDB works with shinyOAuth, which handles the browser sign-in
and token renewal. shinyOAuthDB connects that sign-in to your database
queries or API calls:

1.  Your Shiny app sends the user to a sign-in service, such as
    Microsoft Entra, Google, or Keycloak. This service is the OAuth
    *provider*.
2.  The user signs in and, if asked, approves the access your app
    requests. They enter their password with the provider; your app
    doesn’t collect it.
3.  The browser returns to your Shiny app. shinyOAuth obtains an *access
    token*, a temporary credential for making requests on that user’s
    behalf.
4.  shinyOAuthDB supplies that token when opening a database connection
    or making an API request. The data source checks it and applies the
    user’s permissions.

The data source must be configured to accept tokens from that provider.
Signing in successfully doesn’t give someone access to a database or
table; they also need the relevant database permissions.

## Install

Installing from GitHub builds the package from source. Install the build
tools for your R version first:

- **Windows:** [Rtools](https://cran.r-project.org/bin/windows/Rtools/)
  matching your R version.
- **macOS:** [Xcode Command Line
  Tools](https://mac.r-project.org/tools/), installed with
  `xcode-select --install` in Terminal.
- **Linux:** your distribution’s R development package and C build
  tools; for example, `r-base-dev` and `build-essential` on Debian or
  Ubuntu.

These tools are needed even for HTTP backends that do not need a
database driver.

``` r

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes")
}
remotes::install_github("lukakoning/shinyOAuthDB")
```

This also installs shinyOAuth. Some data sources need an additional R
package or database driver; their guides list the requirements. Add
`build_vignettes = TRUE` to the installation call if you want to read
the guides locally with
[`vignette()`](https://rdrr.io/r/utils/vignette.html).

## Build a small app

The README’s example reads a PostgreSQL table through PostgREST, an HTTP
API for PostgreSQL. It runs Shiny in your R session and starts the
database and Keycloak sign-in service in Docker. You don’t need a cloud
account or a database driver.

Install and start Docker with Linux containers and Docker Compose 2.24.4
or later. Install `jsonlite` for the API responses and `mirai` for
background OAuth requests:

``` r

install.packages(c("jsonlite", "mirai"))
```

Save the following as `example.R` and run `source("example.R")`:

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

# Start PostgreSQL, PostgREST and Keycloak in Docker
demo <- oauth_db_demo("postgrest", action = "services")

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
  auth <- oauth_module_server(
    "auth", client, auto_redirect = FALSE, async = TRUE
  )
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
    onStart = function() {
      onStop(demo$stop)
      mirai::daemons(2)
      onStop(function() mirai::daemons(0))
    }
  ),
  port = 18100,
  launch.browser = FALSE
)
```

The first Docker build takes a few minutes and needs internet access and
several GB of disk space. When Shiny is ready, open
`http://localhost:18100` in your regular browser. Embedded
RStudio/Positron viewers can’t complete the sign-in redirects. Your
browser may ask you to accept Keycloak’s generated local test
certificate.

Sign in as `alice` with password `alice`. The table shows
`alice-visible-1` and `alice-visible-2`. Sign out, then sign in as `bob`
with password `bob`: you’ll see Bob’s rows instead. The app sends the
same request for both users; PostgreSQL’s row policies determine the
result.

Stop the Shiny app to remove the Docker services and sample data. The
`onStop(demo$stop)` call arranges this cleanup. If you start the
services separately, call `demo$stop()` when finished. These accounts
and the client secret are public demo settings; use your own
registration for a real app.

## What each part of the app does

`client` holds the settings for your app’s OAuth registration: where
users sign in, the app’s identity, and the access it requests. Create it
outside `server()`, since every visitor uses the same registration.

[`oauth_ui()`](https://lukakoning.github.io/shinyOAuth/reference/oauth_ui.html)
wraps your Shiny UI so shinyOAuth can handle the browser’s return from
sign-in. Its `id = "auth"` matches the ID passed to
[`oauth_module_server()`](https://lukakoning.github.io/shinyOAuth/reference/oauth_module_server.html);
`uiPattern = ".*"` lets Shiny serve the callback paths too.

Inside `server()`,
[`oauth_module_server()`](https://lukakoning.github.io/shinyOAuth/reference/oauth_module_server.html)
manages sign-in for that visitor’s Shiny session. With
`auto_redirect = FALSE`, the app waits for the **Sign in** button. The
two observers connect the buttons to `auth$request_login()` and
`auth$logout()`.

The app starts two mirai workers once, when the app starts, and stops
them when the app stops. With `async = TRUE`, shinyOAuth uses those
workers for its OAuth network operations, including token exchange and
refresh. A slow identity provider can then be handled without blocking
the app’s R process. See [Enable asynchronous
OAuth](#enable-asynchronous-oauth) for deployment settings and the
separate steps needed for background data fetching.

`auth$connection` is a function that provides the current authorization.
Pass the function, without parentheses, to
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md)
so the API client can check it each time it needs a token. Create this
helper inside `server()` to keep it with the visitor who signed in.

Finally, `$select()` reads the table and returns a data frame for
[`renderTable()`](https://rdrr.io/pkg/shiny/man/renderTable.html).
Before sign-in, the helper waits quietly, like
[`shiny::req()`](https://rdrr.io/pkg/shiny/man/req.html). Because the
call runs inside a reactive output, Shiny updates the table when the
authorization changes and clears it on sign-out. See
[`?oauth_db_postgrest_api`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md)
for filters and other request methods. The `$select()` call itself is
synchronous. For longer requests, use the [background fetching
example](#fetch-data-in-the-background).

## Connect your own data

### Choose your source

Each guide has the source’s setup requirements and a complete app. You
can keep the same sign-in/UI pattern and replace the demo’s provider,
client settings and data helper with the ones in your guide.

For deployment, also follow [async OAuth
setup](#enable-asynchronous-oauth) and [background
fetching](#fetch-data-in-the-background). The source guides’ ordinary
DBI and HTTP calls are synchronous; a worker needs its own native
connection or request, rather than a serialized copy of the guide’s
helper.

See [Recorded backend checks](#recorded-backend-checks) for tested
versions and the parts of each integration that still need deployment
validation.

| Data source | Setup guide |
|----|----|
| PostgreSQL | [Native OAuth](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.md), [PostgREST](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.md), [Supabase](https://lukakoning.github.io/shinyOAuthDB/articles/supabase.md), [Azure PostgreSQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.md), [Google Cloud SQL](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-sql.md) |
| SQL Server | [Azure SQL and SQL Server](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.md) |
| CockroachDB | [CockroachDB](https://lukakoning.github.io/shinyOAuthDB/articles/cockroachdb.md) |
| MongoDB | [Workforce OIDC](https://lukakoning.github.io/shinyOAuthDB/articles/mongodb.md) |
| MySQL | [Azure Database for MySQL](https://lukakoning.github.io/shinyOAuthDB/articles/azure-mysql.md) |
| Cloud data platforms | [Fabric and Power BI](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md), [Databricks](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md), [Snowflake](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md), [BigQuery](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.md), [Redshift](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.md) |
| Query engines | [Trino and Starburst](https://lukakoning.github.io/shinyOAuthDB/articles/trino.md), [Dremio](https://lukakoning.github.io/shinyOAuthDB/articles/dremio.md), [StarRocks](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.md), [SingleStore](https://lukakoning.github.io/shinyOAuthDB/articles/singlestore.md), [ClickHouse](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.md), [DuckDB over Quack](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.md) |
| Other databases and APIs | [libSQL and Turso](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.md), [CrateDB](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.md), [OpenSearch](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.md), [Elasticsearch](https://lukakoning.github.io/shinyOAuthDB/articles/elasticsearch.md), [SAP HANA](https://lukakoning.github.io/shinyOAuthDB/articles/hana.md), [Oracle Database](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md), [Oracle REST Data Services](https://lukakoning.github.io/shinyOAuthDB/articles/oracle-ords.md), [Salesforce](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.md) |

### Register your app

An OAuth app registration tells the provider which application is asking
for access. Create one, or ask your administrator for one, using the
instructions in your source guide. These are the settings you’ll
encounter:

| Setting | What it means |
|----|----|
| Client ID | The provider’s identifier for your app |
| Client secret | Your app’s credential, kept on the Shiny server; some registrations don’t use one |
| Redirect URI | The exact address where the browser returns after sign-in |
| Issuer | The URL identifying the service that issues the tokens |
| Scopes | Permissions your app requests during sign-in |
| Audience | The database or API the access token is intended for |

Most source guides use `http://localhost:8100` as the redirect URI; the
Docker example above uses `http://localhost:18100`. Register the exact
address, including any path and trailing slash, and run Shiny on the
same port. When deploying, register your app’s HTTPS address.

For a self-hosted provider such as Keycloak, follow its [app
registration
instructions](https://www.keycloak.org/docs/latest/server_admin/index.html)
and your source guide. The database must trust that provider and accept
its tokens. Use an access token intended for the data source; an ID
token describes the login and serves a different purpose.

### Save credentials and run the app

Open your app project’s environment file with `file.edit(".Renviron")`
and add the values requested by your source guide, for example:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

Keep `.Renviron` out of Git and restart R after editing it. The source
examples read these values with
[`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html). On a hosting
service, set the variables in the app’s environment settings.

Copy your source guide’s app into `example.R`, replace its connection
settings, and run `source("example.R")`. Open the registered address in
a regular browser. If sign-in works but a query fails, check the token’s
audience and scopes, the user’s database grants, and network access from
the Shiny server to the data source. Keep tokens and secrets out of
logs.

## Query with DBI or dbplyr

DBI is R’s common interface for sending SQL queries to a database and
reading the results. dbplyr lets you write queries with dplyr functions;
it translates them to SQL for the database to run.

For sources that support DBI, the helper returns a reactive function,
usually called `con`. For example, inside `server()` in an Azure SQL
app:

``` r

con <- oauth_db_azure_sql(
  auth$connection,
  server = "example.database.windows.net",
  database = "Reporting"
)

output$rows <- renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT TOP (10) * FROM sales")
})
```

Call `con()` inside each render or reactive expression that queries
data. It checks the current authorization and reuses the visitor’s
connection when possible. For dbplyr, pass `connection` to
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) and use
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
when you need a data frame.

Other sources provide API clients: BigQuery has `$query()`, while Fabric
and Databricks can call functions from their supporting R packages
through `$call()`. The source guide and helper’s function help describe
the methods.

## More ways to try an app

[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a complete local app in Docker, including its R packages and
drivers. Use `oauth_db_demo("postgrest", app = "local")` for an editable
app running in local R with its services in Docker. That mode also needs
`callr` and `bslib` (0.9.0 or later). Run one demo at a time, since they
share ports. See
[`?oauth_db_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
for supported databases, copying files with `action = "files"`, and
recovery with `action = "stop"`.

For a cloud workspace, `oauth_db_cloud_demo("databricks")` guides setup
in the R console and launches an editable local app without Docker. It
also supports Fabric, BigQuery, Snowflake, Azure SQL, Azure PostgreSQL,
Redshift and ClickHouse; their source guides list the requirements.
Enter `?` for help or `cancel` to save an incomplete setup. The launcher
prints a command to resume it. Edit the copied `app.R`, save and reload
the browser to change the query.

Cloud demos use real accounts and existing resources. Queries can
consume compute or query allowances; stopping the demo ends the local
app while shared cloud services keep running. See
[`?oauth_db_cloud_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
for offline drafts, saved settings and script arguments.

## Sessions, saved results and extra permissions

Keep connections and API clients inside `server()`. On sign-out, account
changes or session end, the helpers stop providing the old connection
and call its cleanup method. Driver behavior varies, so call `con()`
before each operation instead of keeping a native connection or copied
token for later use. shinyOAuth handles token renewal. See
[`?oauth_db_connect`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_connect.md)
for token lifetime and connection options.

### Longer queries

The built-in HTTP query methods and ordinary DBI queries run
synchronously. While a query, result download or polling loop waits, it
can delay other Shiny sessions in the same R process. For HTTP clients,
set `timeout` to suit the operation; the helper’s help explains whether
it covers one request or the full operation.

Keep live connections and token callbacks in the Shiny session that
created them. For background work, use the database package’s supported
approach and check the current authorization before displaying a result.
Signing out doesn’t necessarily cancel work already submitted to a
platform.

### Enable asynchronous OAuth

For an app serving several users, enable shinyOAuth’s async path so that
token exchange and refresh do not hold up other sessions in the same R
process. The small app above already does this. In another app,
configure workers once at application startup, outside `server()`, and
stop them at application shutdown:

``` r

mirai::daemons(2)
shiny::onStop(function() mirai::daemons(0))

server <- function(input, output, session) {
  auth <- shinyOAuth::oauth_module_server(
    "auth", client, auto_redirect = FALSE, async = TRUE
  )
  # Add the app's observers and outputs here.
}
```

Setting `async = TRUE` alone is not enough: install mirai and configure
its workers before the module runs. The pool belongs to the app’s R
process, so visitors share it; do not start a pool for each visitor.
Choose its size for your deployment’s memory and concurrency limits. For
an existing future deployment, a non-sequential
[`future::multisession`](https://future.futureverse.org/reference/multisession.html)
plan is another supported backend. A sequential future plan still
blocks. See shinyOAuth’s [async setup
guide](https://lukakoning.github.io/shinyOAuth/articles/usage.html#asynchronous-execution)
for that alternative and its package requirements.

This setting covers shinyOAuth’s module operations. Provider discovery
at app setup, database connections, queries, polling and result
downloads are separate. In particular, it does not change
[`DBI::dbGetQuery()`](https://dbi.r-dbi.org/reference/dbGetQuery.html)
or the built-in HTTP query methods into background operations. The
database helpers also request tokens synchronously; an on-demand token
acquisition can still block, while an already running module refresh
makes reactive callers wait quietly. For an explicitly asynchronous
acquisition, use `grant$access_token(..., async = TRUE)` in the owning
session. See shinyOAuth’s [external integration
guide](https://lukakoning.github.io/shinyOAuth/articles/external-integrations.html#advanced-asynchronous-token-acquisition).

### Fetch data in the background

Use background fetching when a query or download could delay the app.
Shiny’s `ExtendedTask` keeps the visitor’s session responsive while a
promise is pending. Its function must start nonblocking work: wrapping a
synchronous query in `promise_resolve()` or an `async = TRUE` OAuth
module does not move that query off the main process.

The following replaces `server()` in the small PostgREST app above. Add
`actionButton("load", "Load rows")` beside the sign-in buttons in its
UI. Keep its mirai startup and shutdown code. The example reads one page
on a button click, acquiring the token asynchronously in the owning
session and sending only the bearer string and URL to a worker:

``` r

server <- function(input, output, session) {
  auth <- oauth_module_server(
    "auth", client, auto_redirect = FALSE, async = TRUE
  )
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  permissions <- "database.read"
  authorization <- reactive({
    grant <- auth$connection()
    if (is.null(grant) || !grant$has_scopes(permissions)) return(NULL)
    grant
  })
  generation <- reactiveVal(0L)
  previous <- NULL
  observe({
    grant <- authorization()
    if (!identical(grant, previous)) {
      previous <<- grant
      generation(isolate(generation()) + 1L)
    }
  }, priority = 100)

  requested <- reactiveVal(NULL)
  load_rows <- ExtendedTask$new(function(grant, captured) {
    isolate({
      pending <- grant$access_token(
        required_scopes = permissions,
        min_valid_for_seconds = 120,
        async = TRUE
      )
      promises::then(pending, function(token) {
        stale <- isolate(
          session$isClosed() ||
            !identical(authorization(), grant) ||
            !identical(generation(), captured)
        )
        if (stale) return(NULL)
        mirai::mirai({
          response <- httr2::request(url) |>
            httr2::req_url_path_append("visible_rows") |>
            httr2::req_url_query(order = "row_id.asc", limit = 100L) |>
            httr2::req_auth_bearer_token(token) |>
            httr2::req_options(followlocation = FALSE) |>
            httr2::req_timeout(30) |>
            httr2::req_perform()
          httr2::resp_body_json(
            response, simplifyVector = TRUE, bigint_as_char = TRUE
          )
        }, token = token, url = demo$url)
      })
    })
  })
  observeEvent(input$load, {
    req(load_rows$status() != "running")
    grant <- req(authorization())
    captured <- generation()
    requested(captured)
    load_rows$invoke(grant, captured)
  })
  output$rows <- renderTable({
    req(authorization())
    req(identical(requested(), generation()))
    load_rows$result()
  })
}
```

The task includes both token acquisition and the data request. Repeated
clicks while it is running are ignored, and `result()` clears the table
while the next fetch runs. Errors from the current fetch appear in the
output. A changed authorization hides results and errors from older
tasks, including after switching away from an account and back. The
generation counter also changes when the required permission is lost and
restored; ordinary token rotation keeps the same authorization.

This worker uses httr2 directly instead of `$select()`. It reads at most
100 rows and has no pagination or refresh-and-retry policy. Use HTTPS
for a real PostgREST deployment; the URL supplied by the local Docker
demo uses its loopback HTTP endpoint. Adjust the requested token
lifetime to cover worker queueing and the operation. The copied token
cannot refresh itself, and sign-out hides results without guaranteeing
cancellation of the server’s work. OAuth operations and data requests
share the worker pool in this example; allow capacity for token renewal
as well as queries.

For a native database driver, use the same task pattern but open and
close the connection inside the worker, returning data rather than the
connection. Keep `con()`, API clients, authorization objects and token
callbacks in the Shiny process. Fabric and Databricks `$call()` also
accept promise-returning functions and check authorization when their
results resolve; a callback needed by a worker must first be resolved to
a bearer string in its owning session. See the [Shiny background-task
guide](https://shiny.posit.co/r/articles/improve/nonblocking/) for task
buttons and status displays.

### Save query results

Closing a connection doesn’t erase data you’ve already fetched. If you
store results in
[`reactiveVal()`](https://rdrr.io/pkg/shiny/man/reactiveVal.html),
[`eventReactive()`](https://rdrr.io/pkg/shiny/man/observeEvent.html) or
a cache, clear or hide them on sign-out, account changes and loss of
required permissions. A shared cache keyed only by SQL can expose one
user’s results to another. The source checkout’s
`playground/example-query-button.R` shows a query button that clears
saved results when access changes.

### Use an existing login or several accounts

The `*_client()` functions are optional presets; you can keep an
existing shinyOAuth client if it obtains suitable tokens. A named token
*target* selects the service a token is for, such as `"sql"` or
`"storage"` in Microsoft’s presets. Set the helper’s `target` to your
client’s name, or use `target = NULL` for its default token. The [Fabric
guide](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html#use-an-existing-sign-in)
has an example.

`required_scopes` checks permissions before a helper runs. Request those
permissions on the OAuth client first; this argument doesn’t request
consent or grant database privileges. The source guide lists the scopes
its example needs.

For several saved accounts, see
[`vignette("multiple-authorizations", package = "shinyOAuth")`](https://lukakoning.github.io/shinyOAuth/articles/multiple-authorizations.html).
Pass a function such as
`function() auth$connection(shiny::req(input$authorization_id))` to the
database helper. Select IDs from `auth$connections()`; these identify
saved authorizations, separately from token targets.

For another database driver or R package that accepts tokens, see
[`?oauth_db_connect`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_connect.md)
and
[`?oauth_db_token`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md).

## Recorded backend checks

The table distinguishes real database fixtures from mocked service
calls. Versions and results come from the repository’s [validation
record](https://github.com/lukakoning/shinyOAuthDB/blob/main/docs/validation.md)
and integration fixtures, through 9 November 2026. They describe the
tested configurations, rather than a list of every supported server
version.

| Source | Checks and versions | Coverage limit |
|----|----|----|
| CockroachDB | CockroachDB 25.4.0, RPostgres 1.4.10 and libpq 16.10; native JWT validation, per-user grants, token replacement and TLS | Signed fixture tokens; browser sign-in, live JWKS rotation and CockroachDB Cloud are untested |
| Native PostgreSQL | PostgreSQL 18.3, shared libpq 18 and RPostgres 1.4.10; real Keycloak sign-in, user grants and TLS | Native OAuth is tested in Linux containers; Windows uses the unsupported-platform branch |
| PostgREST | PostgREST 16.5 with PostgreSQL 18.3; real sign-in, row policies, writes and TLS | Covers the local deployment, not Supabase’s hosted gateway |
| Trino | Trino 484 and RTrino 0.1.0; real JWT sign-in, user grants and TLS | A Starburst deployment still needs its own configuration check |
| SingleStore | SingleStore 10.9.0 and Connector/ODBC 1.2.1; JWT validation, per-user grants, bound SQL, dbplyr, reconnects and TLS | Signed fixture tokens; browser sign-in, live JWKS rotation and SingleStore Helios are untested |
| StarRocks | StarRocks 3.5.0 and MySQL Connector/ODBC 9.5.0; local JWT sign-in and grants | The Docker app is tested; the Windows local-app driver remains unverified |
| DuckDB over Quack | DuckDB 1.5.4; real JWT validation, server policies and TLS | The Quack client and server must have compatible versions |
| libSQL | libSQL 0.24.33; real signed tokens, database permissions and HTTPS | Hosted Turso external-provider sign-in is not established by this fixture |
| CrateDB | CrateDB 6.4.3; native JWT validation, privileges and HTTPS | Uses a local issuer/JWKS gateway |
| OpenSearch | OpenSearch 3.9.0; Security plugin JWT validation, document/field permissions and HTTPS | Uses a local signing-key configuration; AWS SigV4 requires another client |
| Elasticsearch | Elasticsearch 9.2.0; native JWT realm, document/field permissions, search, SQL, ES\|QL and verified HTTPS | Signed fixture tokens; browser sign-in, live JWKS rotation and Elastic Cloud Hosted are untested; Serverless has no JWT realms |
| ClickHouse | Local SQL/HTTPS fixture uses ClickHouse 26.1.2.11 and checks typed parameters and failed write responses | The fixture proxy supplies authentication; it does not validate ClickHouse Cloud’s custom-JWT feature |
| Azure PostgreSQL | PostgreSQL 18.3 password fixture, RPostgres 1.4.10 and libpq 16.10; real TLS and recovery after credential replacement | Entra token validation and a hosted Azure server are not exercised |
| Azure MySQL | MariaDB Connector/ODBC 3.1.15 and R odbc 1.7.2; local password protocol, 12 KB tokens, credential replacement and verified TLS | Entra token validation, Azure user/group mapping and database grants are untested |
| Databricks | brickster 0.2.15 with a MiniLake fixture for DBI/API results, Arrow and pagination | MiniLake accepts every token and does not enforce grants; it does not validate Databricks authentication |
| Fabric and Power BI | fabricQueryR 1.0.1 routing, callbacks and generated-app checks | Platform calls are mocked; hosted service permissions and native drivers need deployment checks |
| BigQuery | Mocked REST responses cover parameters, polling, pagination, result types and account changes | Google browser sign-in, IAM grants and billed query execution are not covered by these mocks |
| Azure SQL, Snowflake and Redshift | R ODBC connection arguments, credential handling and lifecycle tests | Real vendor drivers and cloud database authentication remain outside the mocked connection boundary |
| Supabase, Oracle REST Data Services and Salesforce | Mocked HTTP responses and complete app definitions | Hosted provider sign-in, server policies and real refresh behavior need configured deployments |
| SAP HANA and Oracle Database | R ODBC boundary, token handling and lifecycle tests; mocked Oracle authentication/context checks | No live SAP HANA or Oracle driver/database/provider combination has been validated |

Cloud demo browser tests use real Keycloak sign-in with mocked platform
operations. They check the local app’s behavior, not the cloud
provider’s app registration or data permissions.
