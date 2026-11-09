# Query Oracle Database as the signed-in user

Read Oracle data in a Shiny app with each visitor's database
permissions. Oracle checks the visitor's access token and maps their
identity to database privileges. The helper opens a DBI connection for
SQL or dbplyr.

## Usage

``` r
oauth_db_oracle(
  authorization,
  host,
  service_name,
  driver,
  ...,
  port = 1522L,
  wallet_location = NULL,
  server_cert_dn = NULL,
  authorization_model = c("global", "end_user"),
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- host:

  One Oracle TCPS listener hostname or IP address.

- service_name:

  Oracle database service name, not a SID or TNS alias.

- driver:

  Registered Oracle ODBC driver name, or its library path when supported
  by the driver manager. Install a client that supports the database's
  OAuth integration; newer integrations need a current client.

- ...:

  Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
  `encoding`, `name_encoding`, or `interruptible`; Oracle ODBC options
  `FBS` (fetch buffer size) and `DBA` (`"R"` for read-only, `"W"` for
  read/write) are also accepted.

- port:

  TCPS listener port. Defaults to `1522`; use the port supplied by your
  administrator, which may differ for self-hosted databases.

- wallet_location:

  Optional Oracle wallet directory for TLS trust or mutual TLS. `NULL`
  uses the Oracle client's configured trust store.

- server_cert_dn:

  Optional expected server certificate distinguished name. `NULL` uses
  Oracle's hostname matching. Certificate matching is always enabled.

- authorization_model:

  `"global"` (the default) for a mapped global database user, or
  `"end_user"` for an individual Oracle Deep Data Security context.
  Choose the model configured by your administrator; see Details.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  Additional OAuth permissions to check before use. Request them on the
  shinyOAuth client first; this check doesn't request consent or grant
  database privileges.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression, then pass the connection to DBI.
Before sign-in, the function waits quietly.

## Details

Install odbc and Oracle Instant Client's Basic and ODBC packages. The
database must trust your provider and audience, map users to database
privileges, and use a compatible Oracle client. The Oracle vignette
explains the provider-specific setup.

Create the helper inside `server()` and call `con()` before each query.
Connections use encrypted TCPS transport with server certificate checks.
Use a wallet when the service requires one.

## Authorization models

The `"global"` model connects as the Oracle global user mapped to the
external identity. The helper checks for `TOKEN_GLOBAL` authentication.

The `"end_user"` model requires Oracle Deep Data Security direct logon
and the jsonlite package. Oracle must establish an end-user context
whose issuer, subject and audience match the supplied JWT. Missing or
mismatched context is an error; the helper doesn't fall back to a
global-schema login.

Keep Entra's `/.default` consent marker in the client configuration. Use
the exact granted database scope in `required_scopes`.

## Connection lifetime

Global-schema connections stay open through token renewal. End-user
connections reopen on the next `con()` call after a token change, so new
role claims reach the database. Sign-out, account changes and session
end close both types. Reopen broken connections through `con()`.

The Oracle driver reads the token from a temporary file, which is
removed after connecting. On Windows, keep R's temporary directory
private to the app's operating-system user. For Oracle web APIs, use
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md).

## See also

[`vignette("oracle", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md).

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_oracle(
  auth$connection,
  host = "database.example.org",
  service_name = "reporting.example.org",
  driver = "Oracle in instantclient_19_30"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT USER AS database_user FROM DUAL")
})
} # }
```
