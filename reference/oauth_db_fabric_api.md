# Call Fabric functions as the signed-in user

List workspaces, query semantic models, or read OneLake data through
fabricQueryR. Pass a function and its usual arguments to `$call()`; the
client supplies the visitor's credentials.

## Usage

``` r
oauth_db_fabric_api(
  authorization,
  targets = list(fabric = "fabric", sql = "sql", dax = "power_bi", kql = "kusto", onelake
    = "storage", graphql = "power_bi"),
  required_scopes = list(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- targets:

  Named vector or list mapping services to shinyOAuth token targets.
  Defaults match
  [`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
  A supplied mapping replaces the defaults. Use `list(kql = NULL)` for
  one service without a named target.

- required_scopes:

  Named list of additional permissions to check, by service. Set client
  and target requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with these methods:

- `$call(.fn, ...)` calls a fabricQueryR function and returns its
  result, including resource objects. Omit `token` from the function
  arguments.

- `$token_provider()` returns a token callback for calling a
  fabricQueryR function directly.

## Details

Create the client inside `server()`. Configure
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
for the services your app needs.

## Resource objects

fabricQueryR objects, such as a Lakehouse, keep the authorization used
to create them. Put the lookup in
[`reactive()`](https://rdrr.io/pkg/shiny/man/reactive.html) so a change
of account obtains a new object. The object's methods can then use the
same sign-in.

Use
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md)
for a DBI connection managed by shinyOAuthDB. Your app must close
connections it opens through fabricQueryR functions or resource methods.

## Custom token targets

The `targets` mapping selects the services the client can use. DAX and
GraphQL share the Power BI resource and must use the same target;
different resources need different targets. Tokens are obtained only
when a service needs them.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md).
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
has sign-in setup and a complete app.

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Microsoft client configured with services = c("fabric", "onelake"):
fabric <- oauth_db_fabric_api(auth$connection)
lakehouse <- shiny::reactive({
  fabric$call(
    fabricQueryR::fabric_item,
    workspace = "workspace-guid",
    item = "lakehouse-guid"
  )
})
output$rows <- shiny::renderTable({
  lakehouse()$read_table("Orders", limit = 100L)
})
} # }
```
