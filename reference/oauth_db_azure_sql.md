# Query Azure SQL as the signed-in user

Read Azure SQL data in a Shiny app using each visitor's Microsoft
account and database permissions. The helper provides a DBI connection
for SQL or dbplyr queries. It also works with SQL Managed Instance and
compatible Synapse SQL endpoints.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- server:

  Database hostname.

- database:

  Database name.

- ...:

  Named odbc connection options, such as `timeout`. The helper sets
  authentication and verified TLS.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  Additional OAuth permissions to check before use. Request them on the
  shinyOAuth client first; this check doesn't request consent or grant
  database privileges.

- driver:

  Installed ODBC driver name.

- port:

  Database port.

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

Install odbc and Microsoft ODBC Driver 18 for SQL Server. Configure the
database for Microsoft Entra sign-in and give users access to the data.
Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "sql"` for sign-in.

Create the helper inside `server()` and call `con()` before querying.
The connection opens on first use and closes when the authorization or
Shiny session ends. See
[`oauth_db_connect()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_connect.md)
for shared session behavior.

For connection names containing ODBC delimiters, use
[`odbc::quote_value()`](https://odbc.r-dbi.org/reference/quote_value.html).

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md).
[`vignette("azure-sql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.md)
has sign-in setup and a complete app.

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
