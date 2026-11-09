# Query SQL Server as the signed-in user

Read SQL Server data in a Shiny app with each visitor's Microsoft
account. The server must accept Microsoft Entra tokens. This is the same
connection helper as
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
with the same arguments.

## Usage

``` r
oauth_db_sql_server(
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

Install odbc and Microsoft ODBC Driver 18 for SQL Server. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "sql"` for sign-in. Create the helper inside `server()`
and call `con()` before querying. See
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md)
for connection requirements and options.

## See also

[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
[`vignette("azure-sql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.md)
has sign-in setup and a complete app.
