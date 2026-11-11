# Fetch data in the background as the signed-in user

Create a task inside `server()` from an existing database helper or API
client. Credentials stay coordinated by the owning Shiny session; each
invocation opens its own connection or client in a mirai worker.

## Usage

``` r
oauth_db_task(source, method = "query", min_valid_for = 120, compute = NULL)
```

## Arguments

- source:

  A database helper such as
  [`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md)
  (pass `con`, not `con()`), or a shinyOAuthDB API client.

- method:

  Operation name. `"query"` uses
  [`DBI::dbGetQuery()`](https://dbi.r-dbi.org/reference/dbGetQuery.html)
  for DBI connections and `$query()` for API clients. `"execute"` uses
  [`DBI::dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html)
  for DBI connections. Other names select native client methods, e.g.
  `"select"` or `"search"`. A self-contained function defined at the top
  level may instead take the worker's connection/client as its first
  argument. Use namespace-qualified functions inside that function.

- min_valid_for:

  Minimum token lifetime requested before dispatch, in seconds. Allow
  for queueing and the operation. Workers do not receive refresh tokens
  and cannot refresh a copied access token.

- compute:

  Optional mirai compute-profile name. Use a separate profile for
  database work to reserve the default pool for OAuth operations.

## Value

A task with `$invoke(...)`, `$result()`, `$status()` and `$cancel()`.
Invocation arguments go to the selected operation. Busy invocations are
ignored and return `FALSE`; accepted invocations return `TRUE`,
invisibly. `result()` waits quietly before completion, checks
authorization on every read, and returns ordinary R data. Native handles
cannot leave the worker. Status is `"initial"`, `"running"`, `"success"`
or `"error"`. Cancelled or invalidated results report `"initial"` until
another invocation is accepted.

## Details

mirai (2.5.1 or newer) is installed with shinyOAuthDB. Configure
[`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html)
once before the server starts, and stop those workers when the app
stops. The task never starts a worker pool itself. Enable `async = TRUE`
on shinyOAuth's module separately for background OAuth operations.

Sign-out, account changes, permission loss and session end invalidate
results and attempt to cancel pending worker work. Cancellation cannot
undo a query or write already accepted by a server. Operations are never
automatically replayed after a credential change. A worker's token
snapshot expires after the requested lifetime budget; HTTP 401 does not
refresh that snapshot or replay the operation. Choose sufficient
lifetime for long polling/downloads.

API tasks reuse the backend's request, parameter, TLS and
result-handling code. Fabric API tasks acquire all token groups
configured on their source; configure `targets` for the services used by
that task. Resolve reactive connection usernames in the owning session;
pass query inputs to `invoke()`.

## Examples

``` r
if (FALSE) { # \dontrun{
# Once at app startup:
mirai::daemons(2)
shiny::onStop(function() mirai::daemons(0))

# Inside server(), with con created by a database helper:
rows <- oauth_db_task(con)
shiny::observeEvent(input$load, rows$invoke("SELECT current_user"))
output$rows <- shiny::renderTable(rows$result())

# An HTTP client uses the same pattern:
orders <- oauth_db_task(postgrest, method = "select")
shiny::observeEvent(input$load_orders, {
  orders$invoke("orders", order = "id.asc", limit = 20L)
})
output$orders <- shiny::renderTable(orders$result())
} # }
```
