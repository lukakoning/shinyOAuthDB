# Query SingleStore as the signed-in user

Query SingleStore or SingleStore Helios using each visitor's database
privileges. The helper supplies their JWT access token to SingleStore's
ODBC driver and returns a DBI connection for SQL or dbplyr queries.

## Usage

``` r
oauth_db_singlestore(
  authorization,
  server,
  database = NULL,
  ...,
  ssl_ca,
  user = "*",
  driver = "SingleStore ODBC Unicode Driver",
  port = 3306L,
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

- server:

  One SingleStore SQL endpoint hostname or IPv4 address, without a
  protocol or port.

- database:

  Optional default database. `NULL` uses the server default.

- ...:

  Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
  `encoding`, `name_encoding`, `interruptible`, `NO_CACHE`,
  `FORWARDONLY`, and `COMPAT_MODE`. Authentication, routing, reconnect
  and TLS settings cannot be overridden.

- ssl_ca:

  Path to a PEM file containing the trusted server CA chain. Required to
  enforce encrypted connections with the SingleStore driver.

- user:

  SingleStore username, or a reactive function returning it. The default
  `"*"` lets SingleStore select the user from its trusted JWT mapping;
  this requires SingleStore 8.1.20 or later.

- driver:

  Installed SingleStore ODBC driver name or library path. Use
  SingleStore Connector/ODBC 1.2.1 or later.

- port:

  SQL endpoint port, default `3306`.

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

Install odbc and SingleStore's ODBC driver. Configure the database to
trust your provider's JWT access tokens and map them to users created
with `authentication_jwt`. Grant those users access to the app's data.
The issuer, audience, scopes and username claim depend on that setup.

Create the helper inside `server()` and call `con()` before each query.
Connections require TLS with certificate and hostname verification.
Driver browser sign-in, keyring credentials and option files are
disabled; shinyOAuth handles sign-in and token renewal.

A changed access token replaces the connection on the next `con()` call.
Token renewal does not rerun completed reactive queries. Account or
username changes, sign-out, lost permissions and session end close the
connection. Failed queries are not replayed. Finish results and
transactions before obtaining another connection after token renewal.

## See also

[`vignette("singlestore", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/singlestore.md)
for database setup, sign-in configuration and a complete Shiny app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_singlestore(
  auth$connection,
  server = "workspace.example.singlestore.com",
  database = "reporting",
  ssl_ca = "path/to/ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT CURRENT_USER() AS database_user")
})
} # }
```
