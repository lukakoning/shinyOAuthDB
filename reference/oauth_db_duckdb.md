# Query a remote DuckDB server as the signed-in user

Query a shared remote DuckDB database with each visitor's access token.
Quack connects your R client to the server, which checks the token and
controls data access. You can query its tables with DBI or dbplyr.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

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

Install duckdb 1.5.3 or later and matching `quack` and `httpfs`
extensions before starting the app. Configure the remote server's OAuth
validator, trusted issuer, audience and data permissions. A local DuckDB
file doesn't provide user sign-in.

Create the helper inside `server()` and call `con()` before each query.
Connections require verified TLS unless you explicitly allow HTTP for
local development with `allow_local_http`.

The helper selects the remote catalog `oauth_remote` and your chosen
schema for table queries. Standalone expressions can still run locally;
query a remote table to check server access.

Token renewal replaces the connection and ends any transaction on it.
Keep transactions within one operation. Sign-out, account changes or
session end close the connection. The helper doesn't replay failed SQL.

## See also

[`vignette("duckdb", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/duckdb.md)
has server requirements, sign-in setup and a complete app.
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local Quack and Keycloak example.

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
