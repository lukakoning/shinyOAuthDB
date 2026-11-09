# SingleStore

SingleStore is a SQL database available on your own infrastructure or as
the hosted SingleStore Helios service.
[`oauth_db_singlestore()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_singlestore.md)
connects with each Shiny visitor’s JWT access token. SingleStore maps
the token to a database user and applies that user’s database
privileges.

The helper returns a DBI connection. You can query tables with SQL or
dbplyr, using the same permissions as the visitor’s other SQL clients.
It selects MySQL’s SQL translations and identifier quoting for dbplyr.

## Before running the app

Install `odbc` in R and [SingleStore
Connector/ODBC](https://docs.singlestore.com/cloud/developer-resources/connect-with-application-development-tools/connect-with-odbc/the-singlestore-odbc-driver/)
1.2.1 or later for your R architecture. Use
[`odbc::odbcListDrivers()`](https://odbc.r-dbi.org/reference/odbcListDrivers.html)
to find its registered name, normally `SingleStore ODBC Unicode Driver`.
The SingleStore driver has its own installation requirements, including
the Linux `glib` and `libsecret` libraries.

Ask your database administrator to configure SingleStore to trust your
provider’s JWT access tokens and map them to database users. The example
uses SingleStore 8.1.20 or later, which can select the database user
from the JWT when the SQL username is `*`.

| Setting | Where to find it |
|----|----|
| SQL endpoint and port | SingleStore workspace or self-hosted aggregator connection details |
| Database | A database the visitor is allowed to query |
| CA certificate file | Trusted PEM CA chain for the SQL endpoint; use the certificate bundle supplied for your deployment |
| OAuth issuer | The sign-in provider whose signing keys SingleStore trusts |
| Client ID and secret | Your [OAuth app registration](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#register-your-app) |
| Access scope and audience | The provider configuration agreed with your database administrator |

Register `http://localhost:8100` as the redirect URI. Configure the
provider to issue JWT access tokens for the database and allow token
renewal. The `database.read` scope below is an example; define or
replace it for your provider. If the provider requires an audience
request parameter, configure that in shinyOAuth’s provider settings.

Save the settings in `.Renviron` and restart R:

``` text
OAUTHDB_CLIENT_ID=your-shiny-app-client-id
OAUTHDB_CLIENT_SECRET=your-shiny-app-client-secret
OAUTHDB_SINGLESTORE_ISSUER=https://login.example.org/realms/reporting
OAUTHDB_SINGLESTORE_SCOPE=database.read
OAUTHDB_SINGLESTORE_SERVER=your-workspace.example.singlestore.com
OAUTHDB_SINGLESTORE_DATABASE=reporting
OAUTHDB_SINGLESTORE_SSL_CA=/path/to/ca.pem
```

## A complete app

This app displays the database user assigned to the visitor. Replace the
query with a table or view they can read after checking the identity.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

scope <- Sys.getenv("OAUTHDB_SINGLESTORE_SCOPE")
provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_SINGLESTORE_ISSUER")
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
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_singlestore(
    auth$connection,
    server = Sys.getenv("OAUTHDB_SINGLESTORE_SERVER"),
    database = Sys.getenv("OAUTHDB_SINGLESTORE_DATABASE", "reporting"),
    ssl_ca = Sys.getenv("OAUTHDB_SINGLESTORE_SSL_CA"),
    required_scopes = scope
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT CURRENT_USER() AS database_user")
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*"),
  port = 8100,
  launch.browser = FALSE
)
```

Save the app as `example.R`, run `source("example.R")`, and open
`http://localhost:8100` in a regular browser. Embedded IDE viewers
cannot complete the OAuth redirects. For a custom SQL port, add
`port = 3307L` with the port supplied by your administrator.

## Configure database access

Follow SingleStore’s JWT setup for [self-managed
databases](https://docs.singlestore.com/db/v9.1/security/authentication/authenticate-via-jwt/)
or
[Helios](https://docs.singlestore.com/cloud/security/database-access/authenticate-via-jwt/).
Configure trusted signing keys, the required audience and a username
claim such as `sub` or `email`. SingleStore’s `jwks_username_field`
setting selects that claim. Use a signing-key endpoint dedicated to the
trusted provider and check the claim requirements for your database
release.

Create JWT-authenticated database users and grant their data privileges.
For example, an administrator could configure one reader with:

``` sql
CREATE USER 'analyst@example.org'@'%'
  IDENTIFIED WITH authentication_jwt REQUIRE SSL;
GRANT SELECT ON reporting.* TO 'analyst@example.org'@'%';
```

The provider must issue the matching username in the configured claim.
Signing in to the Helios portal alone does not make an arbitrary OAuth
token usable for SQL. The helper uses your shinyOAuth access token and
keeps the driver’s separate browser SSO and keyring features disabled.

By default, `user = "*"` lets SingleStore select the JWT’s database
user. To request an explicit user, pass `user = "analyst@example.org"`;
it must match SingleStore’s JWT mapping. A reactive `user` function can
follow a selected account or role. JWT users require SingleStore 7.8.3
or later; using the default wildcard username requires 8.1.20 or later.

## TLS and connection lifetime

The `ssl_ca` file is required. The helper supplies it as `SSLCA` and
sets `SSLVERIFY=1`, so the driver requires TLS and checks the server
certificate and hostname. Supply the CA chain for your deployment,
including a private CA when applicable.

Create the helper inside `server()` and call `connection <- con()`
before each operation. When the access token changes, the next call
replaces the connection. Completed reactive queries do not rerun just
because a token renews. Changing the account or requested username,
signing out, losing required permissions or ending the Shiny session
closes the connection.

Automatic driver reconnects are disabled. A driver-reported invalid
connection is reopened with a current token. Finish pending results and
transactions before obtaining another connection after token renewal.
The helper doesn’t replay failed queries. Clear any results your app
saves when a visitor signs out or changes accounts, as described in
[Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions).
