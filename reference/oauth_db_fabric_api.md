# Call Fabric functions as the signed-in user

Use Fabric services with each visitor's Microsoft account. Pass a
fabricQueryR function to `$call()` to list workspaces, query semantic
models or read OneLake data. The client supplies the user's credentials
and returns the function's result.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

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

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$call(.fn, ...)` calls a fabricQueryR function and returns its
  result, including resource objects. Omit `token` from the function
  arguments.

- `$token_provider()` returns a token callback for calling a
  fabricQueryR function directly.

## Details

Create the client inside `server()` and call its methods from render or
reactive expressions. Configure
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
for the services your app needs first. Users need access to the Fabric
items and data they query.

## Resource objects

A fabricQueryR object, such as a Lakehouse, keeps the authorization used
to create it. Put the lookup inside `reactive()` so it runs again when
the visitor changes accounts, as in the example.

For a DBI connection managed by shinyOAuthDB, use
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md).
Your app must close connections it opens through fabricQueryR functions
or object methods.

## Custom token targets

The `targets` mapping selects the service tokens this client can use.
DAX and GraphQL share the Power BI resource and must use the same
target; different resources need different targets. Tokens are obtained
when a service needs them.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md).
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
has sign-in setup and a complete app.

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
