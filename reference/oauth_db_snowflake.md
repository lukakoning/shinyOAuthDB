# Query Snowflake as the signed-in user

Query Snowflake with each visitor's account and role. A role controls
which data they can access, while a warehouse runs the queries. The
connection works with DBI or dbplyr.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

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

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression, then pass the connection to DBI.
Before sign-in, the function waits quietly.

## Details

Install odbc and the Snowflake ODBC driver. Use
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md)
for Snowflake's own OAuth integration, or a shinyOAuth client for your
external provider. The user needs access to the requested role,
warehouse and data.

Create the helper inside `server()` and call `con()` before each query.
The connection opens on first use and closes when the authorization or
session ends. For names containing ODBC delimiters, use
[`odbc::quote_value()`](https://odbc.r-dbi.org/reference/quote_value.html).

## See also

[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md).
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
has sign-in setup and a complete app.

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
