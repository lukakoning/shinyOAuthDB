# Query Databricks SQL as the signed-in user

Query a Databricks SQL warehouse with DBI or dbplyr through brickster.
Users can sign in with Databricks OAuth or Microsoft Entra.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

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

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function returning a brickster DBI connection.

## Details

Install brickster. Create `con` inside `server()` and get
`connection <- con()` in a render or reactive expression before
querying.

For other brickster functions, use
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).

## Connection lifetime

The helper replaces the connection when its stored token changes. A
saved connection can retain its token after local sign-out; call `con()`
for each operation.

## See also

[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

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
