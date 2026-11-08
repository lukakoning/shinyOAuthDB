# PostgREST

PostgREST turns PostgreSQL tables and functions into a web API. It lets
a Shiny app read database tables over HTTP without installing a
PostgreSQL driver in R.

With
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
each request carries the signed-in visitor’s access token. PostgREST
uses it to select a database role, and PostgreSQL’s grants and row
policies control the result. The same request can therefore return
different rows for different people.

## Set up the server and sign-in

For a configured local example, run
`shinyOAuthDB::oauth_db_demo("postgrest")`. It includes PostgreSQL,
PostgREST, Keycloak and a Shiny app. [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#build-a-small-app)
walks through a smaller app and lists the demo accounts.

For your own data, ask your administrator for an HTTPS PostgREST
endpoint that accepts tokens from your sign-in provider. They must
configure the database roles and table permissions; a server recipe
follows the app.

| Setting | Where to get it |
|----|----|
| `OAUTHDB_POSTGREST_URL` | Your HTTPS API endpoint, including any prefix such as `/rest/v1` |
| `schema`, table | A schema exposed by PostgREST and a table the user can read |
| Issuer, client ID, secret | Your [app registration](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#register-your-app) with the API’s trusted provider |

Register `http://localhost:8100` as the redirect URI. Request the
audience and scopes configured for this API, then save
`OAUTHDB_POSTGREST_ISSUER`, `OAUTHDB_POSTGREST_URL`, `OAUTHDB_CLIENT_ID`
and `OAUTHDB_CLIENT_SECRET` in `.Renviron` and restart R. Use
`ca_bundle` for a private CA.

## Complete Shiny app

Replace the schema, table, and column names with your own. Save the
example as `example.R` and run it with `source("example.R")`.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_POSTGREST_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "email", "offline_access")
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

  postgrest <- oauth_db_postgrest_api(
    auth$connection,
    url = Sys.getenv("OAUTHDB_POSTGREST_URL"),
    schema = "reporting"
  )
  output$rows <- renderTable({
    postgrest$select("orders", order = "id.asc", limit = 20L)
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*"),
  port = 8100,
  launch.browser = FALSE
)

# Open the app in your regular browser at http://localhost:8100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
```

Create the client inside `server()`. Its requests wait quietly before
sign-in and use a current access token for the selected authorization.
Use `target` if your shinyOAuth client has named token targets.

## Filters, embedded resources, and pagination

`filters` contains native PostgREST expressions. Values are URL-encoded;
they are not SQL fragments interpolated by this package. `select` can
include related resources configured through foreign keys.

``` r

rows <- postgrest$select(
  "orders",
  select = "id,total,customers(name)",
  filters = list(total = "gte.100", country = "eq.NL"),
  order = "id.asc",
  limit = 20L,
  offset = 20L
)
response <- postgrest$select(
  "orders",
  order = "id.asc",
  limit = 20L,
  count = "exact",
  raw = TRUE
)
httr2::resp_header(response, "Content-Range")
```

Selections return one page. The server can impose a smaller page size;
use its Content-Range header to inspect the returned range. Exact counts
can be expensive for large tables. See [pagination and
count](https://docs.postgrest.org/en/stable/references/api/pagination_count.html).

Selections return data frames where possible; embedded resources can
produce nested data frames or list columns. Large integers stay as
strings. For exact decimals, have the server return text from a view or
function. See
[`?oauth_db_postgrest_api`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md)
for result formats.

## Functions and native API requests

Call an exposed PostgreSQL function through its RPC endpoint. The keys
in `args` are its argument names; the result may be a scalar, object, or
table.

``` r

total <- postgrest$rpc("order_total", list(order_id = 42L))

# A GET function call runs in a read-only transaction on PostgREST.
total <- postgrest$request(
  c("rpc", "order_total"),
  query = list(order_id = 42L)
)

# Native writes use the same visitor's token and database permissions.
response <- postgrest$request(
  "orders",
  method = "PATCH",
  query = list(id = "eq.42"),
  body = list(status = "reviewed"),
  prefer = "return=representation",
  raw = TRUE
)
```

Reads can refresh and retry once after HTTP 401. Writes and POST
function calls don’t retry automatically, since they may already have
changed data. Results are discarded if the visitor signs out or changes
accounts while a request runs.

## Prepare PostgreSQL, PostgREST and Keycloak

Copy a working configuration with
`oauth_db_demo("postgrest", action = "files")`. In that directory,
`postgrest/fixture.sql` creates an `authenticator` login, database roles
and a row policy. `realm.json` adds the verified token’s `role` claim;
PostgREST switches to that role when executing SQL.

For your deployment, create a restricted login for PostgREST and let it
assume only the roles the API exposes. For example:

``` sql
CREATE ROLE reporting_reader NOLOGIN;
GRANT reporting_reader TO authenticator;
GRANT USAGE ON SCHEMA reporting TO reporting_reader;
GRANT SELECT ON reporting.orders TO reporting_reader;
```

Configure the issuer’s access-token mapper to emit
`role=reporting_reader` and the API’s audience. Set `PGRST_DB_SCHEMAS`
to the exposed schema, `PGRST_JWT_SECRET` to its public JWK/JWKS
material, and `PGRST_JWT_AUD` to that audience. The default role claim
is `role`; configure a different claim path only if your tokens use one.
Plan how to update signing keys when the provider rotates them; the demo
takes a snapshot at startup. Terminate HTTPS at your API or reverse
proxy.

PostgREST’s [authentication
guide](https://docs.postgrest.org/en/v14/references/auth.html) explains
key formats and role extraction. PostgreSQL table grants and row
policies still control which rows the role can access.
