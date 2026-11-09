# Remote libSQL and Turso

libSQL is based on SQLite and can run as a remote database server. Turso
provides hosted databases with compatible SQL APIs. With shinyOAuthDB,
your Shiny app can run SQLite SQL on these servers using the signed-in
visitor’s access token.

[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md)
sends queries over HTTPS and returns data frames, without a database
driver. The server must accept tokens from your sign-in provider.
Self-hosted libSQL and Turso Cloud have different requirements,
explained after the example.

## Try self-hosted libSQL locally

Start Docker and run:

``` r

shinyOAuthDB::oauth_db_demo("libsql")
```

The demo starts self-hosted libSQL, Keycloak sign-in and a Shiny app.
Alice and Bob can read the shared sample table; **Try a write** checks
that the database refuses writes. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#build-a-small-app)
for passwords and cleanup.

Use `oauth_db_demo("libsql", action = "files")` to inspect or change the
configuration. The demo uses self-hosted libSQL; Turso Cloud needs the
separate token setup described below.

## Before running the app

Your server must accept visitor access tokens from your provider.
Self-hosted libSQL and Turso Cloud use different token formats; check
the requirements below with your administrator before reusing an
existing login.

| Setting | Where to get it |
|----|----|
| `OAUTHDB_LIBSQL_URL` | The database’s HTTPS URL, from Turso’s database details or your server administrator |
| `OAUTHDB_LIBSQL_ISSUER` | The provider configured to issue compatible database tokens |
| Client ID and secret | Your [OAuth app registration](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#register-your-app) |
| `OAUTHDB_LIBSQL_AUDIENCE` | The provider’s API audience, if required; leave empty for self-hosted libSQL |

Register `http://localhost:8100` as the redirect URI. The app’s
`sqlite.read` scope is an example your provider must define or replace.
Save the settings in `.Renviron` and restart R:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
OAUTHDB_LIBSQL_ISSUER=https://your-provider.example.org/
OAUTHDB_LIBSQL_URL=libsql://your-database-your-org.turso.io
OAUTHDB_LIBSQL_AUDIENCE=your-provider-api-audience
```

## A complete app

Replace the table name and scopes for your database. The provider’s
token configuration must satisfy the requirements above before running
the app.

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

pkgs <- c("shiny", "shinyOAuth", "shinyOAuthDB", "mirai", "jsonlite")
for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

audience <- Sys.getenv("OAUTHDB_LIBSQL_AUDIENCE")

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_LIBSQL_ISSUER"),
  extra_auth_params = if (nzchar(audience)) {
    list(audience = audience)
  } else {
    list()
  }
)

client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "sqlite.read")
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
  libsql <- oauth_db_libsql_api(
    auth$connection,
    url = Sys.getenv("OAUTHDB_LIBSQL_URL"),
    required_scopes = "sqlite.read"
  )
  query_task <- oauth_db_task(libsql)
  observeEvent(input$load, {
    query_task$invoke(
      "SELECT id, total FROM orders WHERE country = :country LIMIT 20",
      parameters = list(country = "NL")
    )
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

Run `source("example.R")`. The app waits for sign-in before sending SQL
and clears the output on sign-out. Request `offline_access` too if your
provider requires it to renew tokens.

## Parameters and result types

Use an unnamed list for positional `?` parameters, or a named list for
named parameters. The client sends values separately from SQL:

``` r

libsql$query("SELECT * FROM orders WHERE country = ?", list("NL"))
libsql$execute(
  "INSERT INTO events(value) VALUES (:value)",
  list(value = "signed in")
)
libsql$query("SELECT ? AS exact_integer", list(I("9223372036854775807")))
libsql$query("SELECT ? AS bytes, ? AS missing", list(as.raw(c(0, 255)), NULL))
```

SQLite integers return as strings to preserve all 64 bits.
Floating-point values stay numeric; blobs and columns with mixed types
use list columns. Format dates and timestamps as strings in the format
your database uses. See
[`?oauth_db_libsql_api`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md)
for conversions and statement metadata.

## Request lifetime

Each call runs one statement in its own HTTPS request. Calls don’t share
transactions or temporary tables; separate `BEGIN` and `COMMIT` calls
can’t form a transaction. Use a database client with transaction support
when your app needs that behavior.

The helper gets a current token for each call and discards results after
sign-out or account changes. SQL requests don’t retry automatically.
After an ambiguous write failure, check the database before
resubmitting; a statement can finish even after the local app stops
waiting.

## Configure a compatible token issuer

### Self-hosted libSQL

The self-hosted demo uses libSQL 0.24.33. Configure its Ed25519 public
signing key with `SQLD_AUTH_JWT_KEY_FILE` or `SQLD_AUTH_JWT_KEY`,
following the server’s [authentication
instructions](https://github.com/tursodatabase/libsql/blob/main/docs/DOCKER.md#authentication).

Issue the database namespace in `id`, permissions in `a` (`"ro"` for
read-only or `"rw"` for read/write), and an `exp` expiry. Set these
explicitly: the tested server permits missing expiry and defaults
missing permissions to write access. Its newer `p` format is another
option; see the [server token
format](https://github.com/tursodatabase/libsql/blob/main/libsql-server/src/auth/user_auth_strategies/jwt.rs).

This server verifies a configured signing key rather than discovering an
OIDC provider. It rejects an `aud` claim in this configuration. Use a
dedicated key and restrict token issuance to the intended database and
users. A provider that can’t issue this format needs a separate gateway
or token exchange; the R helper doesn’t create or exchange database
tokens.

Expose the server through HTTPS. Use `ca_bundle` for a private
certificate authority.

### Turso Cloud external providers

Follow Turso’s [external authentication
setup](https://docs.turso.tech/sdk/authorization/jwks) for a supported
provider such as Clerk or Auth0. Register the provider’s public
signing-key endpoint and generate a database-specific JWT claims
template with the Turso CLI. Restrict it to the database and operations
the app needs, then configure your provider to issue those claims.

Pass that provider-issued access token through shinyOAuth to the
database. A Turso management token or shared database token doesn’t
carry the visitor’s own permissions.
