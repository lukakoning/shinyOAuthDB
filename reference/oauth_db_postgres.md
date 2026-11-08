# Query self-hosted PostgreSQL as the signed-in user

Connect to PostgreSQL's native OAuth authentication with the visitor's
existing access token. The server validates the token and database role;
queries use RPostgres, DBI or dbplyr.

## Usage

``` r
oauth_db_postgres(
  authorization,
  host,
  dbname,
  user,
  issuer,
  scope,
  ...,
  port = 5432L,
  sslrootcert = NULL,
  connect_timeout = 5L,
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

  One TCP hostname or address.

- dbname:

  Database name.

- user:

  Requested database role, or a function deriving it from the selected
  sign-in's validated identity. PostgreSQL checks that the token may use
  that role according to the server's identity mapping.

- issuer:

  Exact HTTPS issuer identifier configured on PostgreSQL.

- scope:

  Space-separated scopes configured in the server's OAuth authentication
  rule. These scopes are also checked before connecting.

- ...:

  RPostgres result options (`bigint`, `check_interrupts`, `timezone`,
  `timezone_out`), `application_name`, or TCP keepalive options.
  Authentication and TLS options cannot be overridden.

- port:

  TCP port, default `5432`.

- sslrootcert:

  CA certificate bundle path, or `NULL` for libpq defaults.

- connect_timeout:

  Connection timeout in whole seconds, at least two.

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

A reactive function returning an RPostgres DBI connection.

## Details

Native OAuth currently requires Linux, PostgreSQL 18, and shinyOAuthDB
and RPostgres built against the same shared libpq 18. Other platforms
can run the Docker playground. Install libpq without its optional
device-flow module; shinyOAuth handles browser sign-in and token
renewal.

Configure a server-side OAuth validator, its trusted issuer and
audience, database roles and identity mappings before connecting. A
Keycloak setup is included in
[`vignette("postgres", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.md).

Connections use verified TLS and require OAuth. The token hook exists
only during synchronous connection opening and is restored on error or
interrupt. Call `con()` before each operation. A valid connection
survives token refresh; account or role changes and sign-out close it.
Discard a broken native connection and obtain a new one through `con()`;
resetting or cloning a retained native handle is unsupported. Use
separate R processes for workers.

## Try the Docker demo

Run
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
with Docker running to start PostgreSQL 18, Keycloak and a small Shiny
app. The installed package includes the configuration, demo accounts and
sample data. Docker supplies R and the native libraries on Windows,
macOS or Linux.

The [PostgreSQL
guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html)
covers the demo and your own server setup. Use
`oauth_db_demo(action = "files")` to copy and inspect the Docker files.

## See also

[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md)
for Azure's Entra authentication.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside server(), with an OIDC client requesting openid, profile and database.read:
con <- oauth_db_postgres(
  auth$connection,
  host = "postgres.example.org", dbname = "reporting",
  user = function() {
    reference <- shiny::req(auth$connection())
    identity <- reference$identity(claims = "preferred_username")
    shiny::req(identity$id_token_claims$preferred_username)
  },
  issuer = "https://login.example.org/realms/reporting",
  scope = "database.read", sslrootcert = "path/to/ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
