# Query Redshift as the signed-in user

Read Redshift data in a Shiny app using each visitor's database
permissions. The helper opens a DBI connection through Redshift's IAM
Identity Center integration for SQL or dbplyr queries.

## Usage

``` r
oauth_db_redshift(
  authorization,
  server,
  database,
  ...,
  driver = "Amazon Redshift (x64)",
  port = 5439L,
  token_type = c("EXT_JWT", "ACCESS_TOKEN"),
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

- server:

  Database hostname.

- database:

  Database name.

- ...:

  Named Redshift ODBC options, such as `CaFile` or `LoginTimeout`. The
  helper sets authentication and verified TLS.

- driver:

  Installed ODBC driver name.

- port:

  Database port.

- token_type:

  `"EXT_JWT"` for an external provider's JWT access token, or
  `"ACCESS_TOKEN"` for an IAM Identity Center access token.

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

Install odbc and the Redshift ODBC 2.x driver with `IdpTokenAuthPlugin`.
Configure IAM Identity Center to trust your sign-in provider and map
users to database permissions. Your shinyOAuth client must obtain a
token for the audience accepted by that integration.

Create the helper inside `server()` and call `con()` before each query.

## Connection lifetime

Connections open on first use and close after sign-out, account changes
or session end. An established SQL connection stays open through
ordinary token renewal; a new connection gets a current token.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
[`vignette("redshift", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_redshift(
  auth$connection,
  server = "cluster.example.eu-west-1.redshift.amazonaws.com",
  database = "reporting",
  token_type = "EXT_JWT"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
