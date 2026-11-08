# Query Azure SQL as the signed-in user

Query Azure SQL with the visitor's Microsoft account using DBI or
dbplyr. Use this for Azure SQL Database, SQL Managed Instance, or a
compatible Synapse SQL endpoint.

## Usage

``` r
oauth_db_azure_sql(
  authorization,
  server,
  database,
  ...,
  target = "sql",
  required_scopes = character(),
  driver = "ODBC Driver 18 for SQL Server",
  port = 1433L,
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

- database:

  Database name.

- ...:

  Named odbc connection options, such as `timeout`. The helper sets
  authentication and verified TLS.

- target:

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- driver:

  Installed ODBC driver name.

- port:

  Database port.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function returning an odbc DBI connection.

## Details

Install odbc and Microsoft ODBC Driver 18 for SQL Server. The database
must accept Microsoft Entra authentication. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "sql"` to set up sign-in.

Create `con` inside `server()`. In a render or reactive expression, get
`connection <- con()` before calling DBI or dbplyr. Connections open on
first use and close when the authorization or Shiny session ends.

For names containing ODBC delimiters, use
[`odbc::quote_value()`](https://odbc.r-dbi.org/reference/quote_value.html).

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md).
[`vignette("azure-sql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_hana()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_hana.md),
[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside server():
con <- oauth_db_azure_sql(
  auth$connection,
  server = "example.database.windows.net",
  database = "Reporting"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT TOP (20) name FROM sys.tables")
})
} # }
```
