# Google BigQuery

BigQuery is Google’s hosted analytics database. It runs SQL queries as
jobs, so you can query data without managing a database server. A Shiny
app can use each visitor’s Google account and existing data permissions.

You choose a Google Cloud project to run and bill the queries. The data
can live in that project or another one the user can access.
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md)
sends the queries and returns data frames; the first example checks the
signed-in account before reading any tables.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("bigquery")` in the R console for
an editable app. Install `processx` and `askpass` first; no database
driver is needed. The launcher walks you through the query project and
Google app registration.

After sign-in, click **Run example query** to check the Google account.
The demo initially uses the `US` query location; change it to your
dataset’s location before querying tables. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app)
for editing and
[`?oauth_db_cloud_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
for saved settings and script arguments.

## Google Cloud setup

Enable the BigQuery API for the query project. In Google Cloud Console,
open **Google Auth Platform** and configure **Branding** and
**Audience**. If the app is in testing, add the Google accounts that
will try it. Under **Clients**, create a **Web application** with
`http://localhost:8100` as an authorized redirect URI. Google’s [web-app
OAuth
guide](https://developers.google.com/identity/protocols/oauth2/web-server)
explains consent and deployment requirements.

Users need permission to run query jobs in that project and read the
data. BigQuery bills queries to this project. Set `location` to match
your datasets; this example uses `"EU"`.

Save the client ID and secret in a local `.Renviron` file and restart R:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

| Setting | Where to find it |
|----|----|
| `project` | Cloud Console project selector: copy the project **ID**, not its display name or number |
| `location` | BigQuery Explorer: open the dataset’s details and copy its location |
| Client ID and secret | Google Auth Platform **Clients**, the Web application |

Ask the administrator for **BigQuery Job User** on the query project and
**BigQuery Data Viewer** on the relevant datasets, or equivalent
narrower permissions. See [BigQuery IAM
roles](https://docs.cloud.google.com/bigquery/docs/access-control). The
initial identity query still creates a job and needs a query project.

## A complete app

Save this as `example.R`, replacing `"billing-project"` with your
project ID:

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_bigquery_client(
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

  bigquery <- oauth_db_bigquery_api(
    auth$connection,
    project = "billing-project",
    location = "EU"
  )

  query_task <- oauth_db_task(bigquery)

  observeEvent(input$load, {
    query_task$invoke("SELECT SESSION_USER() AS signed_in_user")
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

Run `source("example.R")` and open `http://localhost:8100`. Sign in to
run the query; signing out clears the output.

## Query your data

Replace the identity query with SQL for your tables. Use
`project.dataset.table` names when the data is in another project.

For values entered by a user, pass named R values in `parameters`. This
example assumes a `reporting.Orders` table with a `country` column:

``` r

observeEvent(input$load, {
  query_task$invoke(
    "SELECT * FROM reporting.Orders WHERE country = @country LIMIT 20",
    parameters = list(country = "NL")
  )
})

output$rows <- renderTable(query_task$result())
```

## Find datasets and tables

`$datasets()` lists dataset IDs in the project; `$tables("reporting")`
lists the table IDs in that dataset. Add these outputs inside
`server()`:

``` r

datasets_task <- oauth_db_task(bigquery, method = "datasets")
tables_task <- oauth_db_task(bigquery, method = "tables")

observeEvent(input$load, {
  datasets_task$invoke()
  tables_task$invoke("reporting")
})

output$datasets <- renderPrint(datasets_task$result())
output$tables <- renderPrint(tables_task$result())
```

Add `verbatimTextOutput("datasets")` and `verbatimTextOutput("tables")`
to the UI. To use `reporting` as the default dataset in SQL, set
`dataset = "reporting"` when creating the BigQuery client.

## Query costs and larger results

Set `maximum_bytes_billed = "1000000000"` on `$query()` to limit the
bytes a query may bill. `LIMIT` restricts the rows returned, but doesn’t
provide the same cost limit.

Queries run synchronously and collect all result pages into R memory.
Choose queries whose results fit in memory. A timeout or sign-out stops
fetching results; it doesn’t cancel a submitted BigQuery job.

## Result types

INT64 and decimal columns remain strings to preserve precision. Dates
become `Date`, timestamps become UTC `POSIXct`, and nested or repeated
fields use list columns.

Use `raw = TRUE` to inspect the REST result and schema.
[`?oauth_db_bigquery_api`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md)
describes parameter types and other options. For saved results or
background work, see [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions).
