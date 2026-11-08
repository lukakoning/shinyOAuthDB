# Self-hosted PostgreSQL with OAuth

PostgreSQL is an open-source SQL database. Use it from Shiny with each
visitor’s own login; PostgreSQL checks their token and applies database
grants and row policies. You can query through DBI or dbplyr.

## Try it locally

Start Docker with Linux containers, then run this in R:

``` r

shinyOAuthDB::oauth_db_demo("postgres")
```

Open `http://localhost:18100` once the launcher says it is ready. Sign
in as `alice` / `alice` or `bob` / `bob`. The same query returns only
that person’s rows. Click **Stop demo** or interrupt R to remove the
containers and data.

The package includes PostgreSQL 18, Keycloak configuration and a small
app. Docker supplies the Linux/libpq 18 runtime too. See [Local Docker
demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.md)
for first-build requirements, certificate prompts and editing the app.

## Connect your own database

Native PostgreSQL OAuth needs PostgreSQL 18 and a server-side token
validator. An existing password-based PostgreSQL database needs the
OAuth setup below before you can use it. For Azure’s Entra
authentication, use the separate [Azure PostgreSQL
guide](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.md).

| App value | Where to get it |
|----|----|
| `host`, `port`, `dbname` | Your database administrator or existing PostgreSQL connection settings |
| Issuer | The identity provider’s realm or tenant OpenID configuration |
| Client ID and secret | A registration for your Shiny app; see [OAuth setup](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.md) |
| Scope | The database’s OAuth rule and the matching scope in the identity provider |
| Username claim | The profile field that matches the database’s identity-to-role mapping |
| `sslrootcert` | The CA certificate that signed the database’s TLS certificate |

The next app assumes these values are ready. The server configuration
and native R runtime instructions follow it.

## A complete app

Create a shinyOAuth client for your own issuer. Request `profile` and
configure the provider to include `preferred_username` in the validated
ID token. This example assumes that username matches the PostgreSQL role
provisioned for that person, as in the Docker fixture. Set
`OAUTHDB_POSTGRES_ISSUER`, `OAUTHDB_CLIENT_ID`, and
`OAUTHDB_CLIENT_SECRET` before running the app.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- Sys.getenv("OAUTHDB_POSTGRES_ISSUER")
provider <- oauth_provider_oidc_discover(issuer, id_token_validation = TRUE)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
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
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_postgres(
    auth$connection,
    host = "postgres.example.org",
    dbname = "reporting",
    user = function() {
      reference <- req(auth$connection())
      identity <- reference$identity(claims = "preferred_username")
      req(identity$id_token_claims$preferred_username)
    },
    issuer = issuer,
    scope = "database.read",
    sslrootcert = "path/to/ca.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user AS database_user")
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

`user` is the database role requested when opening a PostgreSQL
connection. The callback derives it from the currently signed-in
account’s validated identity, so signing in as a different person
changes the requested role. PostgreSQL checks that the access token is
allowed to use that role and applies its grants and row policies.

If your database roles differ from the provider’s usernames, adapt the
callback to your server’s identity-to-role mapping. The subjects mapped
to `alice` and `bob` above are Docker fixture configuration, not a list
of visitors to hardcode into a deployed app. A fixed `user` is
appropriate only when the deployment intentionally maps the permitted
identities to one shared database role.

## Prepare PostgreSQL and the identity provider

PostgreSQL’s native OAuth needs an installed token-validation module.
The example uses Percona’s `pg_oidc_validator`, pinned and patched to
validate the database audience. Copy the demo files with
`oauth_db_demo(action = "files")`; `postgres/Dockerfile` and
`postgres/patches/validator-audience.patch` show the build.

Register a Web OAuth client in Keycloak with your Shiny callback URL,
authorization code flow and PKCE. Configure the database access token’s
audience and the `database.read` scope. The fixture’s `realm.json`
provides a complete example, including demo subjects, audience mappers
and scopes.

Configure PostgreSQL’s validator to check token signatures, issuer,
expiry, audience and the required scope. Map the validated subject to a
database role. A corresponding `pg_hba.conf` rule looks like:

``` text
hostssl reporting alice,bob 10.0.0.0/24 oauth issuer="https://login.example.org/realms/reporting" scope="database.read" validator=pg_oidc_validator map=keycloak_subjects
```

In `pg_ident.conf`, map the real Keycloak subjects to roles:

``` text
keycloak_subjects 11111111-1111-4111-8111-111111111111 alice
keycloak_subjects 22222222-2222-4222-8222-222222222222 bob
```

Those subjects are examples from the local fixture; use your provider’s
real values. Create the roles, grant database access, and configure
table grants and row policies. The installed demo contains complete
files under `postgres/config/` and SQL under
`postgres/sql/01-fixture.sql`.

## Build the native R runtime

The current native adapter supports Linux with libpq major version 18.
Both RPostgres and shinyOAuthDB must link the same shared libpq
instance. Build libpq with `--without-libcurl` and leave the optional
`libpq-oauth` device-flow module uninstalled. shinyOAuth obtains tokens
through browser sign-in; a retained broken database handle must not
start another login.

For a custom Linux image, install libpq’s development files and
`pkg-config`, point `PKG_CONFIG_PATH` and the dynamic library search
path at that libpq, then build RPostgres and shinyOAuthDB from source:

``` r

install.packages("RPostgres", type = "source")
Sys.setenv(SHINYOAUTHDB_POSTGRES_OAUTH = "required")
install.packages(".", repos = NULL, type = "source")
```

Run the last command from the shinyOAuthDB checkout, or replace `"."`
with the path to its source directory or source tarball. Setting
`SHINYOAUTHDB_POSTGRES_OAUTH` to `required` makes installation fail if
the native adapter cannot be built. The default, `auto`, builds it when
the required Linux/libpq 18 development files are available. `disabled`
builds the other backends without this adapter. Windows and macOS can
use `oauth_db_demo("postgres")`.

## Connection lifetime

Call `con()` before every operation. A valid connection survives
ordinary token refresh. Sign-out, permission loss, account changes and
Shiny session end close it. After a connection failure, obtain a new
handle through `con()`; resetting or cloning a retained native handle is
unsupported. Use separate R processes for separate workers.

PostgreSQL documents [OAuth
authentication](https://www.postgresql.org/docs/18/auth-oauth.html) and
[validator
modules](https://www.postgresql.org/docs/18/oauth-validators.html). The
source repository’s [native and browser
tests](https://github.com/lukakoning/shinyOAuthDB/tree/main/integration/postgres-keycloak)
exercise the same authentication mechanism with additional failure
cases.
