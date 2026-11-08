# Query Snowflake as the signed-in user

Query Snowflake with the visitor's account and role using DBI or dbplyr.
Set the warehouse, database, and schema for your queries, or use the
account's defaults.

## Usage

``` r
oauth_db_snowflake(
  authorization,
  server,
  database = NULL,
  schema = NULL,
  warehouse = NULL,
  role,
  ...,
  required_scopes = paste0("session:role:", role),
  target = NULL,
  driver = "SnowflakeDSIIDriver",
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

  Database hostname.

- database, schema, warehouse:

  Optional connection settings. `NULL` uses the driver's or account's
  defaults.

- role:

  Snowflake role for this connection.

- ...:

  Named Snowflake ODBC connection options. Authentication and the HTTPS
  protocol cannot be overridden.

- required_scopes:

  Permissions to check before use. The default is the Snowflake role
  scope, `paste0("session:role:", role)`. For External OAuth, supply the
  scope names configured by the integration.

- target:

  Named shinyOAuth token target, or `NULL` for the default token.

- driver:

  Installed ODBC driver name.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function returning an odbc DBI connection.

## Details

Install odbc and the Snowflake ODBC driver. Use
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md)
for Snowflake's own OAuth integration, or a shinyOAuth client configured
for your External OAuth provider.

Create `con` inside `server()` and get `connection <- con()` inside a
render or reactive expression before querying. The helper opens the
connection on first use and closes it when the authorization or session
ends.

For names containing ODBC delimiters, use
[`odbc::quote_value()`](https://odbc.r-dbi.org/reference/quote_value.html).

## See also

[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md).
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_snowflake(
  auth$connection,
  server = "organization-account.snowflakecomputing.com",
  role = "REPORTING_READER",
  warehouse = "REPORTING_WH",
  database = "ANALYTICS"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT CURRENT_USER(), CURRENT_ROLE()")
})
} # }
```
