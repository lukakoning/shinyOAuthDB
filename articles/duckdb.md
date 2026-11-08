# Remote DuckDB with OAuth

DuckDB is an open-source analytical SQL database, often used inside R.
Here it runs as a remote server through Quack, DuckDB’s network
protocol. Use
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md)
to query a remote DuckDB Quack server with each visitor’s OAuth access
token. The connection works with DBI and dbplyr. A local DuckDB file has
no OAuth login; this helper connects to a server that validates tokens
and enforces its own data access policy.

## Try the local Quack demo

With Docker running, launch the configured server and Shiny app:

``` r

shinyOAuthDB::oauth_db_demo("duckdb")
```

Sign in as Alice or Bob using the [demo
accounts](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html#start-a-demo).
Both can read the shared sample table. **Try a write** demonstrates that
the server rejects writes. Docker supplies DuckDB 1.5.4, matching Quack
extensions, `quack_oauth` and Keycloak. It uses a prebuilt R client
where available; compiling the client on other platforms takes longer.
The installed `duckdb/server.py` and `realm-extended.json` show the
validator, audience and `quack:read` scope configuration.

## Before running the app

This example needs a remote Quack server that accepts OAuth tokens, plus
R’s `duckdb` package (1.5.3 or later) with matching `quack` and `httpfs`
extensions. The server and extension setup follows the app.

| Setting | Where to get it |
|----|----|
| `host`, `port` | The remote Quack server or its TLS proxy; the example uses HTTPS port 443 |
| Table name | A table in the remote catalog you are allowed to read |
| Issuer, client ID, secret | An [OAuth registration](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.md) with the server’s trusted provider |
| `quack:read` | The default quack_oauth read scope; your provider must issue it |
| `ca_bundle`, if needed | The CA for a privately signed server certificate |

Set `OAUTHDB_DUCKDB_ISSUER`, `OAUTHDB_CLIENT_ID` and
`OAUTHDB_CLIENT_SECRET` in `.Renviron`, then restart R. A local
`.duckdb` file has no user sign-in.

## A complete app

Replace the hostname, port and table name for your deployment. This
example uses port 443 for a TLS proxy; Quack’s default port is 9494.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_DUCKDB_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "quack:read")
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

  con <- oauth_db_duckdb(
    auth$connection,
    host = "duckdb.example.org",
    port = 443,
    required_scopes = "quack:read"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT * FROM orders LIMIT 20")
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

Run `source("example.R")`. The app waits for sign-in before connecting
and clears the output on sign-out. Get a connection inside each render
or reactive expression before running queries.

For dbplyr, use `dplyr::tbl(con(), "orders")`. The helper attaches the
remote catalog as `oauth_remote` and selects its `main` schema. Pass
`schema` to select another remote schema. Table queries use the attached
catalog; standalone expressions such as `SELECT current_user` can run
locally and do not prove which remote principal the server
authenticated.

## Install extensions and prepare the server

Use compatible DuckDB and Quack versions on both sides. The R client
needs `duckdb` 1.5.3 or later and its matching `quack` and `httpfs`
extensions. Quack’s interface has changed between releases, so test your
chosen versions together.

``` r

install.packages("duckdb")
connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
DBI::dbExecute(connection, "INSTALL quack")
DBI::dbExecute(connection, "INSTALL httpfs")
DBI::dbDisconnect(connection, shutdown = TRUE)
```

Keep extensions in a directory the app can use across R sessions, for
example by setting `DUCKDB_EXTENSION_DIRECTORY` before provisioning and
running the app. The helper loads Quack inside a private in-memory
DuckDB instance.

On the server, configure an OAuth validator such as
[quack_oauth](https://github.com/DataZooDE/quack-oauth). Follow that
extension’s installation and server configuration instructions for your
DuckDB version and server platform. A client can connect even when
quack_oauth is unavailable for its own platform: only the server loads
it. Configure its trusted issuer and audience, select its authentication
and authorization callbacks, and define the scopes and data access
policy each visitor needs. Quack’s default shared token check does not
validate OAuth tokens.

Expose the server through TLS with a certificate trusted by the DuckDB
client, typically through a reverse proxy. See [Quack
security](https://duckdb.org/docs/current/quack/security). Pass
`ca_bundle = "path/to/private-ca.pem"` if the server uses a private CA.
The helper explicitly enables TLS, including for loopback hosts. For
local development only, `allow_local_http = TRUE` permits HTTP on
`localhost`, `127.0.0.1` or `[::1]`.

`quack_oauth` also has client-side OAuth flows. They are unnecessary
here: shinyOAuth handles browser sign-in and renewal; the helper passes
only the resulting access token to Quack. It creates no persistent token
secrets.

## Register the Shiny app

Register an OAuth client with the server’s identity provider and allow
`http://localhost:8100` as a redirect URI. Request access tokens for the
audience configured on the Quack server. An ID token or a token issued
for another API cannot substitute for this access token.

This example uses an OIDC provider and the `quack:read` scope from
quack_oauth’s default policy. Configure the provider to issue that scope
and the correct audience. Use your server’s scopes if its policy
differs. Request `offline_access` too if your provider requires it for
renewal. For providers requiring a resource parameter or named token
target, configure that on the shinyOAuth client and pass the target name
to
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md).

Save your registration in `.Renviron` and restart R:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
OAUTHDB_DUCKDB_ISSUER=https://login.example.org/realms/reporting
```

## Connection lifetime

Call `con()` before each operation. Quack receives a token when
attaching, so the helper closes and replaces the connection when the
access token changes. This ends transactions and discards temporary
client state on the old connection. Keep a transaction within one
synchronous operation and get a new handle for the next operation.

Account changes, lost required permissions, sign-out and Shiny session
end close the connection and shut down its private DuckDB instance. A
caller retaining a raw handle must still obtain `con()` before each
operation; the server decides whether an existing remote session remains
authorized. The helper never retries SQL statements or replays a
transaction.

Setup errors omit the token-bearing SQL statement. An attachment failure
can mean an unavailable endpoint, a rejected TLS certificate or token,
denied catalog access, or an unknown schema. Check server diagnostics
and confirm the issuer, audience and scopes match the app registration.

For several accounts and saved results, see [Authentication and
sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.md).

## Test the integration locally

The source checkout includes a [Docker
fixture](https://github.com/lukakoning/shinyOAuthDB/tree/main/integration/duckdb-oauth)
with a real quack_oauth server, a JWKS issuer and a TLS proxy. It
generates its own signed test tokens and certificates. From the
repository root, run `Rscript --vanilla tools/check-duckdb-oauth.R` with
Docker running and the test dependencies installed. The checks cover
DBI/dbplyr reads, rejected writes, invalid tokens and TLS verification
without production credentials.
