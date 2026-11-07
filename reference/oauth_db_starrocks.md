# Query StarRocks as the signed-in user

Open a DBI connection to StarRocks using its JWT authentication plugin
and MySQL Connector/ODBC's OpenID Connect client plugin.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

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

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function returning an odbc DBI connection.

## Details

Configure StarRocks 3.5 or later with `authentication_jwt` or a JWT
security integration, a trusted JWKS, issuer, audience, and principal
claim. Configure shinyOAuth to obtain a JWT access token accepted by
that integration. This helper supplies the access token; it does not
substitute an ID token or launch the driver's own browser flow.

The driver reads the token from a temporary file during synchronous
connection opening. The file is created in a private temporary directory
and removed on success, error, or interrupt. On Windows its access rules
inherit from R's temporary directory; use a private user temporary
location. TLS verifies the server identity. DSNs, option files, and
competing credentials cannot be supplied through `...`. Parameter
binding uses the driver's client-side prepared statements (`NO_SSPS=1`)
for compatibility with StarRocks' MySQL protocol.

Create the helper inside `server()` and call `con()` before each
operation. Valid SQL sessions survive ordinary token renewal; account or
username changes and sign-out close them. Reopen a broken connection
through `con()`; the original token file no longer exists after
connection opening.

## See also

[`vignette("starrocks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.md).

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

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
