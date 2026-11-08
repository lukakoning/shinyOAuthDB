# Query Fabric SQL as the signed-in user

Read data from a Fabric Warehouse, Lakehouse SQL analytics endpoint, or
SQL Database with DBI. The default ODBC backend also supports dbplyr.
Queries use the visitor's Microsoft account.

## Usage

``` r
oauth_db_fabric_sql(
  authorization,
  server,
  database = NULL,
  ...,
  backend = c("odbc", "adbc"),
  target = "sql",
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

  Database hostname.

- database:

  Database name.

- ...:

  Arguments for
  [`fabricQueryR::fabric_sql_connect()`](https://kennispunttwente.github.io/fabricQueryR/reference/fabric_sql_connect.html),
  such as `read_only` and `timeout`.

- backend:

  SQL driver interface: `"odbc"` (default) or `"adbc"`.

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

A reactive function returning a DBI connection.

## Details

Install fabricQueryR and the SQL driver. Copy the server and database
from the item's SQL connection settings. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "sql"` for sign-in.

Create `con` inside `server()` and get `connection <- con()` inside a
render or reactive expression before querying. The helper reuses the
connection and closes it when the authorization or session ends.

## SQL drivers

The default ODBC backend supports DBI and dbplyr. To use ADBC for DBI or
Arrow queries, install adbi, adbcdrivermanager and the external MSSQL
driver (version 1.5.0 or later), then pass `backend = "adbc"`. Use ODBC
for dbplyr's SQL Server translations; the ADBC connection does not
currently select that dialect.

ADBC connections reopen with a current token when `con()` is next called
after token renewal. This closes outstanding results on the old
connection. Consume and release results before starting another
operation.

Direct DBI reads use the driver's type conversions. For fabricQueryR's
exact numeric conversion, call
[`fabricQueryR::fabric_sql_query()`](https://kennispunttwente.github.io/fabricQueryR/reference/fabric_sql_query.html)
through
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md)
with `backend = "adbc"` and `numeric_policy = "exact"`.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md).
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_fabric_sql(
  auth$connection,
  server = "example.datawarehouse.fabric.microsoft.com",
  database = "Reporting"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT TOP (20) name FROM sys.tables")
})
} # }
```
