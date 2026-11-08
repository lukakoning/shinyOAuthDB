# Oracle REST Data Services

Use
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md)
to read protected Oracle REST Data Services (ORDS) resources and call
JSON handlers with each visitor’s OAuth token. It uses HTTPS without
Oracle client libraries. For a native DBI connection, see [Oracle
Database](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md).

## Set up ORDS and sign-in

An ORDS administrator must REST-enable the required schema resources and
protect them with ORDS privileges. Configure a JWT profile with the
expected issuer, audience and signing keys. Map the token’s scopes or
roles to the resource privileges. ORDS documents external-provider JWT
profiles from release 23.3, including providers such as OCI IAM Identity
Domains, Keycloak, Auth0 and Okta. Follow the [ORDS authentication
guide](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.3/orddg/developing-REST-applications.html).

Register an authorization-code client with PKCE at the trusted provider
and add `http://localhost:8100` as a redirect URI. Configure the client
to receive a JWT with the audience and access scope ORDS expects.
Request OpenID Connect scopes for the Shiny sign-in. Enable refresh
tokens when requesting `offline_access`, or use the provider’s
documented alternative.

Save the app settings in `.Renviron` and restart R:

``` text
OAUTHDB_CLIENT_ID=your-shiny-app-client-id
OAUTHDB_CLIENT_SECRET=your-shiny-app-client-secret
OAUTHDB_ORDS_ISSUER=https://login.example.org/realms/reporting
OAUTHDB_ORDS_SCOPE=reports.read
OAUTHDB_ORDS_URL=https://data.example.org/ords/reporting
```

Use the ORDS schema alias URL, including any reverse-proxy prefix. The
example assumes that `orders/` is a protected AutoREST collection.
Register resources and database access rules before running it.

## A complete app

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

scope <- Sys.getenv("OAUTHDB_ORDS_SCOPE")
provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_ORDS_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "offline_access", scope),
  required_scopes = scope
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    verbatimTextOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  ords <- oauth_db_oracle_ords_api(
    auth$connection,
    url = Sys.getenv("OAUTHDB_ORDS_URL"),
    required_scopes = scope
  )
  output$rows <- renderPrint({
    ords$select("orders", query = list(limit = 20L))$items
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*"),
  port = 8100,
  launch.browser = FALSE
)
```

Save this as `example.R`, run `source("example.R")`, and open
`http://localhost:8100` in a regular browser. Sign in to read one page
of the collection. Use `offset` and `limit` to page explicitly.
Responses retain `items`, `hasMore`, offsets and links as native JSON
lists; large JSON integers are strings. Server-provided links are never
followed.

For a custom JSON handler, call its relative path:

``` r

result <- ords$request(
  c("api", "sales"),
  query = list(country = "NL"),
  trailing_slash = TRUE
)
```

`select()` appends a trailing slash for AutoREST collections.
`request()` uses the path exactly, with `trailing_slash = TRUE` when the
resource needs one. The client rejects redirects instead of sending
credentials to a different endpoint. Use `raw = TRUE` to inspect a
successful httr2 response. POST, PUT and PATCH can send a JSON `body`;
the API is not a DBI connection or a SQL-result parser.

## User identity and data access

ORDS validates the JWT and enforces its resource privileges. The JWT
subject is available to handlers as `:current_user`. An ORDS role is not
automatically an Oracle database role, and accepting a user JWT does not
by itself change the database schema used by a handler. Configure
handler filtering or a supported end-user security context to enforce
the required per-user data access. Verify two users with different
permissions before deployment.

Each operation gets a current token and stays tied to the authorization
it started with. Responses arriving after sign-out or account
replacement are discarded. GET and HEAD can refresh and retry once after
HTTP 401. POST, PUT, PATCH and DELETE are never replayed automatically.
The client does not follow redirects or pagination links. It returns
native JSON responses from custom handlers without interpreting
application-specific success fields.

Automated tests mock ORDS responses and cover token renewal, scope
checks, account isolation, routing, errors and request replay rules. No
live ORDS or Oracle database was available for integration validation.
