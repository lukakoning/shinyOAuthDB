# Query Azure PostgreSQL as the signed-in user

Query Azure Database for PostgreSQL with a visitor's Microsoft account.
The connection works with DBI or dbplyr through RPostgres.

## Usage

``` r
oauth_db_azure_postgres(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 5432L,
  sslrootcert = NULL,
  target = "postgres",
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

  PostgreSQL hostname.

- dbname:

  Database name.

- user:

  Database role created for the user or their group.

- ...:

  RPostgres result options (`bigint`, `check_interrupts`, `timezone`,
  `timezone_out`), `connect_timeout`, `application_name`, or TCP
  keepalive options. Authentication and TLS options cannot be
  overridden.

- port:

  Database port.

- sslrootcert:

  CA certificate bundle path, or `NULL` to use libpq's configured
  bundle.

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

Install RPostgres linked to libpq 16 or later. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "postgres"`. The server must accept Entra
authentication, and the database role must already exist.

Create the helper inside `server()` and get `connection <- con()` inside
a render or reactive expression before querying. The connection uses
verified TLS and requires password authentication with the visitor's
access token. GSS encryption is disabled, and the server cannot select
Kerberos, certificate-only, or trust authentication instead.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
[`vignette("azure-postgres", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
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
con <- oauth_db_azure_postgres(
  auth$connection,
  host = "example.postgres.database.azure.com",
  dbname = "reporting",
  user = "reporting-readers",
  sslrootcert = "path/to/root-ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
