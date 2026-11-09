# Neo4j

Use
[`oauth_db_neo4j_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_neo4j_api.md)
to run Cypher queries with each Shiny visitor’s account. Neo4j validates
their access token and applies the database roles mapped to that
identity. Queries return data frames; graph objects stay in list
columns. Install `jsonlite` alongside shinyOAuthDB. No database driver
is needed.

This integration uses the HTTPS Query API v2. Self-managed servers need
Neo4j Enterprise with SSO configured for JWT access tokens. Aura needs
an SSO-enabled tier and configuration that accept the same user tokens
at its database Query API. An Aura console login or management API
credential alone does not establish that configuration.

## Get the connection settings

Ask your database administrator for the database’s HTTPS Query API base
URL and name, plus the identity provider’s issuer, required scopes and
token audience. Use a maintained Neo4j 5.26 LTS patch or a newer
supported release. Query API v2 starts with Neo4j 5.19. Self-managed
versions before 5.25 must enable `QUERY_API_ENDPOINTS` in
`server.http_enabled_modules`. Keep the server’s Bolt connector enabled:
Neo4j uses it internally to execute Query API requests. Shiny only needs
network access to the HTTPS endpoint.

For a self-managed server, the HTTPS port defaults to `7473`. Aura uses
HTTPS on port `443`. Supply the base URL rather than the query endpoint:

``` r

graph <- oauth_db_neo4j_api(
  auth$connection,
  url = "https://graph.example.org:7473",
  database = "neo4j"
)
```

The client appends `/db/neo4j/query/v2`. Keep any reverse-proxy prefix
in `url`. A `neo4j+s://` or `bolt://` URI is for a Bolt driver and
cannot be used here. For a private certificate authority, pass its PEM
bundle with `ca_bundle`.

## Register the Shiny app

Register a web application with the provider trusted by Neo4j. Use
`http://localhost:8100` as the example’s redirect URI, then save these
settings in `.Renviron` and restart R:

| Setting | Value |
|----|----|
| `OAUTHDB_NEO4J_URL` | Database HTTPS base URL |
| `OAUTHDB_NEO4J_DATABASE` | Database name, for example `neo4j` |
| `OAUTHDB_NEO4J_ISSUER` | Provider’s HTTPS issuer URL |
| `OAUTHDB_CLIENT_ID`, `OAUTHDB_CLIENT_SECRET` | Shiny app’s OAuth registration |

The example requests `graph.read`, which your provider must define or
replace. Configure the audience to match the Neo4j OIDC provider. Some
providers need an `audience` authorization parameter; pass that through
the provider’s `extra_auth_params`. A scope name alone does not set the
audience or grant Neo4j privileges. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#register-your-app)
for registration terminology and token settings.

## A complete app

This example queries `Person` nodes. Replace the label, properties and
scope with those used by your database. The user’s Neo4j roles must
permit reading the selected nodes and properties.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_NEO4J_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "graph.read")
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

  graph <- oauth_db_neo4j_api(
    auth$connection,
    url = Sys.getenv("OAUTHDB_NEO4J_URL"),
    database = Sys.getenv("OAUTHDB_NEO4J_DATABASE", "neo4j"),
    required_scopes = "graph.read"
  )
  output$rows <- renderTable({
    graph$query(
      "MATCH (p:Person) WHERE p.country = $country RETURN p.name AS name, p.country AS country LIMIT 20",
      parameters = list(country = "NL")
    )
  })
}

runApp(shinyApp(ui, server, uiPattern = ".*"),
  port = 8100, launch.browser = FALSE)
```

Open `http://localhost:8100` in your regular browser to sign in.

## Configure Neo4j SSO and permissions

Configure an OIDC authentication and authorization provider on Neo4j
Enterprise. Set its discovery URL or explicit issuer and JWKS URL,
expected audience, username claim and group-to-role mapping. The
username claim should normally be the provider’s stable `sub`. Ensure
the provider puts the groups needed for authorization in the access
token.

For example, the administrator can map an identity-provider group to a
Neo4j role. Grant that role access to the database and the relevant
nodes and properties, and use different mappings when visitors should
see different data. The Shiny app then runs the same query for every
visitor; Neo4j controls the visible graph.

Use an access-token configuration. Some Neo4j SSO examples use ID
tokens, but this client supplies only the visitor’s OAuth access token.
Register the Shiny callback separately from any Neo4j Browser callback.

See Neo4j’s [SSO integration
settings](https://neo4j.com/docs/operations-manual/current/authentication-authorization/sso-integration/)
and [provider
examples](https://neo4j.com/docs/operations-manual/current/tutorial/tutorial-sso-configuration/).
For Aura, check the [SSO availability and
configuration](https://neo4j.com/docs/aura/security/single-sign-on/) for
your tier and verify database query access with the intended user
tokens.

## Parameters, graph values and writes

Pass values separately from Cypher using a named list. Nested named
lists become maps, and unnamed lists become arrays. Missing scalars and
`NULL` become JSON null. Numeric values must be finite. To send a large
integer exactly, pass a string and use `toInteger($id)` in Cypher; for
dates and timestamps, use `date($day)` or `datetime($at)` with ISO
strings or R `Date`/`POSIXct` values.

Project scalar properties for a table. Returning whole nodes, paths or
relationships puts their native JSON values in list columns:

``` r

people <- graph$query(
  "MATCH (p:Person) WHERE p.name = $name RETURN p, p.name AS name",
  parameters = list(name = "Alice")
)
people$p[[1L]]$properties

result <- graph$query(
  "MATCH (p:Person) RETURN p.name AS name LIMIT 20",
  raw = TRUE
)
result$data$fields
result$data$values
result$notifications
```

`raw = TRUE` returns the parsed response and metadata after checking for
query errors. It does not bypass authorization checks. Results use
[plain JSON](https://neo4j.com/docs/query-api/current/plain-json/):
large JSON integers remain strings, while temporal, spatial and binary
values keep the server’s string representation. Mixed values stay in
list columns; empty or entirely null columns are logical because this
format has no column schema. There is no automatic paging; bound large
results in Cypher.

Use `$execute()` when you want the server’s update counters:

``` r

counters <- graph$execute(
  "CREATE (:Person {name: $name, country: $country})",
  parameters = list(name = "Alice", country = "NL")
)
counters$nodesCreated
```

Each call submits one statement in an auto-commit transaction. The
client does not retain bookmarks or manage explicit multi-request
transactions; queries use the server’s default routing and consistency
behavior.

## Token lifetime and failures

Create the client inside `server()`, then call it from render or
reactive expressions. Each operation gets a current token. The client
rejects a response if the authorization changes or loses required scopes
while the request runs, and it cannot be reused in another Shiny
session.

POST queries and writes never retry automatically, including after a
401. HTTP 202 can still contain a Neo4j query error, so the client
checks the response body before returning rows or counters. A timeout or
lost response does not establish whether a write committed. Check the
database before resubmitting it, and discard saved results and bookmarks
on sign-out or account changes.

The native integration check uses Neo4j 5.26.32 Enterprise with locally
signed JWTs and real database roles. It covers database token
validation, graph privileges and HTTPS; it does not establish browser
sign-in, live provider key rotation, clustering or Aura compatibility.
