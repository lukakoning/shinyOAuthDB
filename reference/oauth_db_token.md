# Get a user's access token for another R package

Get the visitor's current access token for an R function that accepts
one directly. An access token is a temporary credential for making
requests on the user's behalf. The returned function gets a current
token each time you call it.

## Usage

``` r
oauth_db_token(
  authorization,
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

A reactive function, such as `bearer`. Call `bearer()` inside a render
or reactive expression to get the current token string.

## Details

Create the helper inside `server()`. shinyOAuth obtains or renews the
token when needed. Call `bearer()` for each request; a token string
saved earlier still has its original expiry time.

For Fabric and Databricks,
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md)
and
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md)
can supply credentials to their supporting packages for you.

## See also

[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).
See
[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md)
for token lifetime.

## Examples

``` r
if (FALSE) { # \dontrun{
bearer <- oauth_db_token(auth$connection, required_scopes = "all-apis")
output$rows <- shiny::renderPrint({
  brickster::db_sql_warehouse_list(
    host = "example.cloud.databricks.com",
    token = bearer()
  )
})
} # }
```
