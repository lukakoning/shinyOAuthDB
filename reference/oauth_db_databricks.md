# Query Databricks SQL as the signed-in user

Query Databricks tables with each visitor's account and data
permissions. You connect to a SQL warehouse, which supplies the compute
for queries. The connection works with DBI or dbplyr through the
brickster package.

## Usage

``` r
oauth_db_databricks(
  authorization,
  host,
  warehouse_id = NULL,
  ...,
  http_path = NULL,
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

- warehouse_id:

  SQL warehouse ID. Supply this or `http_path`.

- ...:

  brickster connection options, such as `catalog` and `schema`.

- http_path:

  Warehouse HTTP path, such as `"/sql/1.0/warehouses/warehouse-id"`.
  Supply this or `warehouse_id`.

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

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression, then pass the connection to DBI.
Before sign-in, the function waits quietly.

## Details

Install brickster and use
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md)
for Databricks sign-in. The user needs access to the workspace, SQL
warehouse and data. For Azure Databricks with Entra, use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "databricks_entra"` and set `auth_mode = "entra"` here.

Create the helper inside `server()` and call `con()` before each query.
Use
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md)
to call other brickster functions.

## Connection lifetime

The helper replaces the connection when its token changes. A saved
brickster connection can retain its old token after sign-out, so obtain
the current connection through `con()` for every operation.

## See also

[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_databricks(
  auth$connection,
  host = "example.cloud.databricks.com",
  warehouse_id = "warehouse-id"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user()")
})
} # }
```
