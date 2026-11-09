# Query Fabric SQL as the signed-in user

Read tables from a Fabric Warehouse, Lakehouse SQL endpoint or SQL
Database using each visitor's Microsoft account. The helper provides a
DBI connection for SQL queries; its default ODBC backend also supports
dbplyr.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

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

Install fabricQueryR and the SQL driver. Copy the server and database
from the Fabric item's SQL connection settings. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "sql"` for sign-in. Users need access to the item and
its data.

Create the helper inside `server()` and call `con()` before querying.
The helper reuses the connection and closes it when the authorization or
Shiny session ends.

## SQL drivers

Use the default ODBC backend for DBI and dbplyr's SQL Server
translations. For ADBC queries through DBI or Arrow, install adbi,
adbcdrivermanager and the external MSSQL driver (1.5.0 or later), then
set `backend = "adbc"`. ADBC doesn't select dbplyr's SQL Server dialect.

After token renewal, ADBC replaces the connection on the next `con()`
call. Consume and close outstanding results before starting another
operation.

DBI reads use the driver's type conversions. For fabricQueryR's exact
numeric conversion, call
[`fabricQueryR::fabric_sql_query()`](https://kennispunttwente.github.io/fabricQueryR/reference/fabric_sql_query.html)
through
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md)
with `backend = "adbc"` and `numeric_policy = "exact"`.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md).
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
has sign-in setup and a complete app.

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
