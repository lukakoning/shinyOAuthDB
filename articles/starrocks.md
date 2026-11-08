# StarRocks

StarRocks is an open-source SQL engine for analytics. Query StarRocks
with DBI or dbplyr using each visitor’s JWT access token. The connection
uses StarRocks’s MySQL protocol and MySQL Connector/ODBC’s OpenID
Connect client plugin.

## Try the local demo

With Docker running, `shinyOAuthDB::oauth_db_demo("starrocks")` starts a
configured server, Keycloak and an app with Alice and Bob’s accounts.
See [Local Docker
demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.md)
for credentials and cleanup. StarRocks uses amd64 images and needs about
4 GB of Docker memory.

## Values for your own server

Run `install.packages("odbc")` in R, then install [MySQL
Connector/ODBC](https://dev.mysql.com/doc/connector-odbc/en/connector-odbc-installation.html)
9.2 or later with its OpenID Connect plugin. Your StarRocks 3.5+ server
must accept JWT access tokens; the detailed server setup follows the
app.

| Setting | Where to get it |
|----|----|
| `OAUTHDB_STARROCKS_SERVER` | The cluster’s MySQL endpoint hostname; the default port is 9030 |
| `database` | The StarRocks database your users can query |
| `OAUTHDB_STARROCKS_DRIVER` | The registered driver name from [`odbc::odbcListDrivers()`](https://odbc.r-dbi.org/reference/odbcListDrivers.html) |
| `OAUTHDB_STARROCKS_SSL_CA` | The CA certificate for that endpoint |
| Issuer, client ID, secret | Your [OIDC app registration](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html#use-keycloak-with-a-self-hosted-database) |

Save the `OAUTHDB_*` values in `.Renviron` and restart R. The app
requests the database username from the login; configure the matching
principal claim on StarRocks.

## Complete Shiny app

Register your app with the trusted identity provider and configure its
audience and scopes for StarRocks. Use `http://localhost:8100` as the
local redirect URI. Set `OAUTHDB_STARROCKS_ISSUER`,
`OAUTHDB_STARROCKS_SERVER`, `OAUTHDB_STARROCKS_DRIVER`,
`OAUTHDB_STARROCKS_SSL_CA`, `OAUTHDB_CLIENT_ID`, and
`OAUTHDB_CLIENT_SECRET` in your environment. The example uses the
validated ID token’s preferred username; select the claim your server
maps.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_STARROCKS_ISSUER")
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
  con <- oauth_db_starrocks(
    auth$connection,
    server = Sys.getenv("OAUTHDB_STARROCKS_SERVER"),
    database = "reporting",
    user = function() {
      reference <- req(auth$connection())
      identity <- reference$identity(claims = "preferred_username")
      req(identity$id_token_claims$preferred_username)
    },
    driver = Sys.getenv("OAUTHDB_STARROCKS_DRIVER"),
    ssl_ca = Sys.getenv("OAUTHDB_STARROCKS_SSL_CA")
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

# Open the app in your regular browser at http://localhost:8100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
```

Save this as `example.R`, replace the database and claim mapping, and
run `source("example.R")`. Use `target` when your shinyOAuth client
contains named token targets. No separate browser authentication is
performed by the database driver.

## Configure server authentication and the driver

Use StarRocks 3.5 or later with JWT authentication. Configure a trusted
JWKS, the exact issuer and audience, and a principal claim that maps to
the StarRocks username. Grant the user or group its database privileges.
See [JWT
authentication](https://docs.starrocks.io/docs/administration/user_privs/authentication/jwt_authentication/)
and [security
integrations](https://docs.starrocks.io/docs/administration/user_privs/authentication/security_integration/).

Install the R package `odbc` and MySQL Connector/ODBC 9.2 or later,
including its `authentication_openid_connect_client` plugin. A MariaDB
driver or an older MySQL driver is not sufficient. List installed driver
names with
[`odbc::odbcListDrivers()`](https://odbc.r-dbi.org/reference/odbcListDrivers.html)
and pass the registered name as `driver`. On Unix, a driver library path
may also be accepted by the driver manager. Windows requires the driver
to be installed and registered. Set `plugin_dir` if the driver cannot
find its installed authentication plugins. See MySQL’s [authentication
options](https://dev.mysql.com/doc/connector-odbc/en/connector-odbc-configuration-authentication.html).

Enable TLS for the StarRocks MySQL endpoint. The helper requires server
identity verification; supply `ssl_ca` for a private CA. Use the
hostname in the server certificate. The default query port is 9030.

The helper uses the visitor’s **access token** from shinyOAuth.
Configure the provider and StarRocks to accept that JWT with its issuer,
audience, and principal claim. A provider that issues only opaque access
tokens, or an integration that accepts only that provider’s ID tokens,
needs a different provider configuration before using this helper.

## Connection lifetime and queries

Call `con()` before every operation. The helper keeps a valid SQL
connection through normal token refresh, replaces it when the account or
resolved username changes, and disconnects it on sign-out or session
end.

``` r

connection <- con()
DBI::dbGetQuery(connection, "SELECT id, total FROM orders LIMIT 20")
dplyr::tbl(connection, "orders") |>
  dplyr::filter(total >= 100) |>
  dplyr::collect()
```

MySQL Connector/ODBC accepts its JWT through the `openid-token-file`
connection option. The helper writes it into a private temporary
directory only while opening the connection, then removes the file on
success, error, or interrupt. On Windows the directory inherits access
rules from R’s temporary directory, which must be private to the app
user.

An open SQL session may remain usable after its login token expires,
depending on the server. Reopen a broken connection through `con()`; do
not reconnect, clone, or pool a saved handle using its former token
file. Queries and mutations are never replayed by this package.

The HTTP SQL API documents Basic authentication. This backend
deliberately uses the documented JWT plugin through the MySQL protocol;
it does not assume that a bearer header authenticates the HTTP SQL
endpoint.
