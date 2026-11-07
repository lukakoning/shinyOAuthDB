# Call Databricks functions as the signed-in user

Call brickster functions to list warehouses, run SQL, or use other
Databricks APIs. The client supplies the workspace host and the user's
credentials.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- host:

  Databricks workspace hostname or HTTPS origin.

- auth_mode:

  `"databricks_oauth"`, or `"entra"` for Azure Databricks with Microsoft
  sign-in.

- target:

  Token target name. Defaults to `"databricks"` for Entra. Databricks
  OAuth uses the authorization's default token.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with `$call(.fn, ...)`. Pass a brickster function as `.fn`
and its usual arguments through `...`, omitting `host` and `token`. The
method returns the function's result. `$warehouses(timeout = 30)` lists
visible SQL warehouses as a data frame with `id`, `name` and `state`,
following all result pages. Listing doesn't start a warehouse or
establish permission to run queries.

## Details

Create the client inside `server()`. Set the authentication options when
creating it; `$call()` uses those settings.

## Longer operations

Each call obtains a current token. Polling and fetching within that
brickster call keep the supplied token. The client doesn't retry the
operation or close connections returned by the function.

## See also

[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md)

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
