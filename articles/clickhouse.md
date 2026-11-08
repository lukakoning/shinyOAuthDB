# ClickHouse

ClickHouse is a SQL database for analytics. This guide uses a service
configured to accept OAuth JWT access tokens. Run SQL against a
JWT-enabled ClickHouse service using each visitor’s account. The client
uses ClickHouse’s HTTPS interface and returns data frames without an
ODBC or native ClickHouse driver.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("clickhouse")` in your R console.
This guided example uses Microsoft Entra as the custom JWT issuer. It
first asks whether your qualifying Cloud service already trusts that
issuer and maps its audience and role claims. Choose **Not ready yet**
to save a draft and get setup links, then resume with
`jwt_ready = "yes"` when configured.

The remaining settings are `url` (HTTPS database query endpoint),
`tenant_id`, accepted API `resource`, full delegated `scope` and Shiny
`client_id`. The API resource’s token version, issuer, audience and role
values must match the service configuration. With Entra v2 access
tokens, configure the resource API to issue v2 tokens; its App ID URI
and token audience can differ. Your administrators should verify the
mapping.

Install `processx`, `jsonlite` and `askpass`; no database driver is
needed. A confidential client uses masked input or
`OAUTHDB_CLICKHOUSE_CLIENT_SECRET`. The local editable app waits for
**Run example query** and leaves the Cloud service running when stopped.
An optional `database` selects a default for later table queries. See
[Guided cloud
demos](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.md).

A standard trial or built-in `clickhouse-client --login` does not
establish this custom-provider flow. Check the [documented
availability](https://clickhouse.com/blog/introducing-jwt-authentication-in-clickhouse-cloud)
before arranging an account for this demo. Other OIDC providers can use
the manual example below; their client configuration differs from this
guide.

## Prepare a JWT-enabled service

Custom identity providers need a qualifying **ClickHouse Cloud
Enterprise** service. An ordinary ClickHouse Docker container doesn’t
supply this authentication feature. The service configuration follows
the app.

| Setting | Where to find it |
|----|----|
| `OAUTHDB_CLICKHOUSE_URL` | Your service’s **Connect** dialog, HTTPS endpoint, commonly port 8443 |
| `OAUTHDB_CLICKHOUSE_ISSUER` | The issuer trusted by the service’s JWT settings |
| Client ID and secret | Your [Shiny registration](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.md) with that identity provider |
| Database roles | Existing ClickHouse roles mapped from the token’s role claims |

Save the `OAUTHDB_*` values in `.Renviron` and restart R. You need no
additional R database driver.

## Complete Shiny app

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_CLICKHOUSE_ISSUER")
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
  clickhouse <- oauth_db_clickhouse_api(
    auth$connection,
    url = Sys.getenv("OAUTHDB_CLICKHOUSE_URL")
  )
  output$rows <- renderTable({
    clickhouse$query(
      "SELECT currentUser() AS database_user, version() AS server_version"
    )
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

Save the example as `example.R` and run `source("example.R")`. Set
`database` when creating the API client to choose a default database.
Use `target` for a named shinyOAuth token target, and `ca_bundle` for a
private certificate authority supported by your curl TLS backend.

## Enable service JWT authentication

Custom identity providers currently require **ClickHouse Cloud
Enterprise** and service version 26.4 or later, or 26.8 for EC signing
keys. Configure the trusted issuer, audience, and public HTTPS JWKS
endpoint in the service’s JWT authentication settings. Map the
provider’s roles claim to roles that exist in ClickHouse, and grant
those roles the required database permissions. See [JWT authentication
and
availability](https://clickhouse.com/blog/introducing-jwt-authentication-in-clickhouse-cloud).

Use the database’s HTTPS query endpoint, commonly port 8443. A Cloud
management API key, database password, or the fact that a server speaks
ClickHouse SQL does not establish JWT database authentication. This
helper requires a deployment that accepts the visitor’s bearer access
token.

Register your Shiny app with the trusted identity provider, using
`http://localhost:8100` for the local redirect URI. Configure the
audience, scopes, and role claims that ClickHouse expects. The example
assumes the provider issues the intended JWT access token through its
normal authorization-code flow; it does not invoke
`clickhouse-client --login`.

Set `OAUTHDB_CLICKHOUSE_ISSUER`, `OAUTHDB_CLICKHOUSE_URL`,
`OAUTHDB_CLIENT_ID`, and `OAUTHDB_CLIENT_SECRET` in your environment.

## Native typed parameters

SQL goes in the POST body. Parameter values are supplied separately
through ClickHouse’s `param_` mechanism and are never interpolated into
SQL.

``` r

rows <- clickhouse$query(
  "SELECT id, total FROM reporting.orders WHERE country = {country:String} AND id > {after:UInt64} LIMIT 20",
  parameters = list(country = "NL", after = "9007199254740993")
)
day <- clickhouse$query(
  "SELECT {day:Date} AS day",
  parameters = list(day = as.Date("2026-11-03"))
)
at <- as.POSIXct("2026-11-03 12:00:00", tz = "Europe/Amsterdam")
times <- clickhouse$query(
  "SELECT {at:DateTime('UTC')} AS at, {precise:DateTime64(6, 'UTC')} AS precise",
  parameters = list(at = at, precise = at + 0.125)
)
```

Supply one R scalar per parameter. Missing values use the native
nullable representation; declare a compatible `Nullable(...)` type in
SQL. Supply large integers and exact decimals as strings.

`POSIXct` values are formatted as UTC wall-clock strings, regardless of
their R display timezone. Use `DateTime('UTC')` for whole seconds and
`DateTime64(6, 'UTC')` for fractional seconds; encoding retains up to
six fractional digits. Always specify `'UTC'` in the SQL placeholder. An
unqualified type uses the server or session timezone, and a different
timezone annotation changes the instant represented by the formatted
string. In the example, noon in Amsterdam becomes `11:00:00` UTC.

Array and tuple parameters use native ClickHouse literal strings wrapped
in [`I()`](https://rdrr.io/r/base/AsIs.html), such as
`parameters = list(ids = I("[1,2,3]"))`.
[`I()`](https://rdrr.io/r/base/AsIs.html) preserves a value already
encoded in ClickHouse’s escaped format; it remains a bound HTTP
parameter and is never interpolated into SQL.

## Results and statements

The client requests JSONCompact, which retains column order and
duplicate column names. Omit FORMAT clauses and output-format overrides
from your SQL. Integers of 64 bits or more and decimals remain strings;
smaller integers and floats become R numbers. Dates become `Date`,
timestamps keep their server string representation, and complex values
become list columns. Empty queries preserve their column metadata.

``` r

result <- clickhouse$query(
  "SELECT count() AS rows FROM reporting.orders",
  raw = TRUE
)
result$meta
result$statistics

clickhouse$execute(
  "INSERT INTO reporting.reviewed_orders (id) VALUES ({id:UInt64})",
  parameters = list(id = "9007199254740993")
)
```

`execute()` invisibly returns the httr2 response for successful
statements. All requests obtain a current token for the authorization
that started them. Authorization changes discard late responses. SQL
requests never retry automatically, including after HTTP 401, because a
statement may already have executed. Redirects are rejected.

Response buffering and complete JSON parsing prevent returning partial
rows after a server exception. Operations collect results in R memory. A
timeout or sign-out does not guarantee cancellation of a submitted
query. Configure query limits in ClickHouse for long-running work. See
the [HTTP interface](https://clickhouse.com/docs/interfaces/http).
