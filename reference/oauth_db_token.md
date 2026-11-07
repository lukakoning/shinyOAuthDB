# Get a user's access token for another R package

Use this when an R function accepts an access token directly. Call the
returned function for a current token each time you make a request.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

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

A reactive function returning a bearer token string. Call `bearer()`
inside the user's Shiny session.

## Details

For Fabric or Databricks functions, the platform API clients below can
supply the credentials for you.

shinyOAuth obtains or renews the token. Keep the function in the Shiny
session and get a token for each operation; a copied token string keeps
its own expiry time.

## See also

[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).
See
[`vignette("authorization", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.md)
for token lifetime.

Other advanced connection helpers:
[`oauth_db_connect()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_connect.md),
[`oauth_db_fabric()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric.md)

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
