# Query Redshift as the signed-in user

Query Redshift with a visitor's own access using DBI or dbplyr. This
helper connects through Redshift's IAM Identity Center integration.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

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

A reactive function returning an odbc DBI connection.

## Details

Install odbc and the AWS Redshift ODBC 2.x driver with
`IdpTokenAuthPlugin` support. The deployment must trust your app's
sign-in provider and map users to database permissions. Configure a
shinyOAuth client for that provider and the required token audience.

Create `con` inside `server()` and call it before querying in a render
or reactive expression.

## Connection lifetime

Connections open on first use and close on authorization changes,
sign-out, or session end. Ordinary token refresh preserves an
established SQL connection; a new connection obtains a current token.

## Authentication options

The helper passes the token to the driver's `IdpTokenAuthPlugin`. Use
one of the two `token_type` values above. Identity-enhanced IAM
credentials and `SUBJECT_TOKEN` use separate authentication flows.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
[`vignette("redshift", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_hana()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_hana.md),
[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

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
