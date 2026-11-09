# Call Databricks functions as the signed-in user

Use Databricks APIs with each visitor's account. Pass a brickster
function to the client's `$call()` method to list warehouses, run
queries or perform other supported operations. The client supplies the
workspace and the visitor's current token.

## Usage

``` r
oauth_db_databricks_api(
  authorization,
  host,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
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

- host:

  Databricks workspace hostname or HTTPS origin.

- auth_mode:

  `"databricks_oauth"`, or `"entra"` for Azure Databricks with Microsoft
  sign-in.

- target:

  Token target name. Defaults to `"databricks"` for Entra. Databricks
  OAuth uses the authorization's default token.

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

A client object with `$call(.fn, ...)`. Pass a brickster function as
`.fn` and its usual arguments through `...`, omitting `host` and
`token`. The method returns the function's result.
`$warehouses(timeout = 30)` lists visible SQL warehouses as a data frame
with `id`, `name` and `state`, following all result pages. Listing
doesn't start a warehouse or establish permission to run queries.

## Details

Create the client inside `server()` and call its methods from render or
reactive expressions. Choose authentication settings when creating the
client; `$call()` supplies them to the brickster function. Use
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md)
for a DBI connection managed by shinyOAuthDB.

## Longer operations

Each brickster call gets a current token. Polling and fetching within
that call keep the supplied token. Operations don't retry automatically.
Your app must close any connections returned by brickster functions.

## See also

[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
databricks <- oauth_db_databricks_api(
  auth$connection,
  host = "example.cloud.databricks.com"
)
output$warehouses <- shiny::renderPrint({
  databricks$call(brickster::db_sql_warehouse_list)
})
} # }
```
