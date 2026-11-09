# Query StarRocks as the signed-in user

Query StarRocks data with each visitor's account and database
privileges. The helper opens a DBI connection for SQL or dbplyr, using
the visitor's signed access token to authenticate.

## Usage

``` r
oauth_db_starrocks(
  authorization,
  server,
  database,
  user,
  driver,
  ...,
  port = 9030L,
  ssl_ca = NULL,
  plugin_dir = NULL,
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

  One StarRocks frontend hostname or address.

- database:

  Default StarRocks database.

- user:

  StarRocks username, or a reactive function returning it. The server
  must map the token's principal claim to this username.

- driver:

  Registered MySQL Connector/ODBC driver name. Some driver managers also
  accept a library path. Install version 9.2 or later, including its
  OpenID Connect plugin.

- ...:

  Connection options: `timeout`, `timezone`, `timezone_out`, `bigint`,
  `encoding`, `name_encoding`, `interruptible`, `readtimeout`,
  `writetimeout`, `NO_CACHE`, `FORWARD_CURSOR`, `NO_CATALOG`,
  `NO_SCHEMA`, or `DFLT_BIGINT_BIND_STR`.

- port:

  MySQL protocol port, default `9030`.

- ssl_ca:

  Trusted CA certificate file, or `NULL` for driver defaults.

- plugin_dir:

  Directory containing the driver's authentication plugins, or `NULL`
  for its installed default.

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

Install odbc and MySQL Connector/ODBC 9.2 or later with its OpenID
Connect plugin. Configure StarRocks 3.5 or later to accept JWT access
tokens from your provider and map their identity claim to the requested
`user`. The connection uses verified TLS; supply `ssl_ca` for a private
CA.

Create the helper inside `server()` and call `con()` before each query.
Valid connections stay open through ordinary token renewal. Account or
username changes and sign-out close them. Reopen a broken connection
through `con()` to obtain a current token.

The driver briefly reads the token from a temporary file, which the
helper removes after connecting. On Windows, keep R's temporary
directory private to the app's operating-system user. Authentication and
TLS options are managed by the helper.

## See also

[`vignette("starrocks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.md).

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_starrocks(auth$connection,
  server = "starrocks.example.org", database = "reporting",
  user = function() {
    reference <- shiny::req(auth$connection())
    identity <- reference$identity(claims = "preferred_username")
    shiny::req(identity$id_token_claims$preferred_username)
  },
  driver = "MySQL ODBC 9.2 Unicode Driver", ssl_ca = "path/to/ca.pem")
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT CURRENT_USER()")
})
} # }
```
