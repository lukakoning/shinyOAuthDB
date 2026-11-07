# Query a remote DuckDB server as the signed-in user

Attach a DuckDB Quack server using the visitor's OAuth access token and
query its tables with DBI or dbplyr. The server must validate OAuth
tokens, for example with the quack_oauth extension.

## Usage

``` r
oauth_db_duckdb(
  authorization,
  host,
  port = 9494L,
  schema = "main",
  ca_bundle = NULL,
  allow_local_http = FALSE,
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

- host:

  One TCP hostname or address. Enclose IPv6 addresses in brackets.

- port:

  Quack server or TLS proxy port, default `9494`.

- schema:

  Default schema in the remote database, default `"main"`.

- ca_bundle:

  Optional CA certificate bundle path for a private server CA.

- allow_local_http:

  Allow unencrypted HTTP for `localhost`, `127.0.0.1` or `[::1]`.
  Defaults to `FALSE`; use only for local development.

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

A reactive function returning a DuckDB DBI connection.

## Details

Install duckdb 1.5.3 or later and its matching `quack` and `httpfs`
extensions. Provision them before starting the app with `INSTALL quack`
and `INSTALL httpfs` in DuckDB. The helper loads them in a separate
in-memory database for each connection. TLS and certificate verification
are required, including on loopback unless `allow_local_http = TRUE`.
Use a certificate trusted by the DuckDB client.

shinyOAuth manages sign-in and token renewal. Only the access token is
passed to Quack; the client does not need quack_oauth or persistent
secrets. Configure the server's trusted issuer, audience and
authorization policy.

Call `con()` before each operation. A changed access token replaces the
connection because Quack authenticates at attachment time. This also
ends any transaction on the old connection. Account changes, lost
permissions, sign-out and session end shut down the private DuckDB
instance. Queries and failed statements are never replayed by the
helper.

The remote catalog is attached as `oauth_remote` and selected as the
default database, so unqualified table names use its selected schema.
SQL runs through DuckDB's attached-catalog interface; local expressions
and functions can still execute on the client.

## See also

[`vignette("duckdb", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.md)
has server requirements, sign-in setup and a complete app.
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local Quack and Keycloak example.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside server(), using a client for the Quack server's issuer and audience:
con <- oauth_db_duckdb(
  auth$connection, host = "duckdb.example.org", port = 443,
  required_scopes = "quack:read"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT * FROM orders LIMIT 20")
})
} # }
```
