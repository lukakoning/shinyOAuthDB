# Get a token callback for one Fabric service

Use this to call a fabricQueryR function directly with the visitor's
credentials. It supplies the callback expected by the function's `token`
argument. For several services or resource objects, use
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md).

## Usage

``` r
oauth_db_fabric(
  authorization,
  service = c("fabric", "sql", "dax", "kql", "onelake", "graphql"),
  target = .odb_fabric_profile(service)$target,
  required_scopes = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- service:

  One of `"fabric"`, `"sql"`, `"dax"`, `"kql"`, `"onelake"`, or
  `"graphql"`.

- target:

  Token target name. Defaults to the service's preset target. Use `NULL`
  if the authorization has no named targets.

- required_scopes:

  Additional permissions to check. `NULL` uses the service's read/query
  defaults.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function. Call `callback()` to get the function to pass as
fabricQueryR's `token` argument.

## Details

Create the helper inside `server()`. The callback obtains and renews
tokens through shinyOAuth. It stays tied to the authorization that
created it.

## See also

[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md).
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
has sign-in setup and a complete app.

Other advanced connection helpers:
[`oauth_db_connect()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_connect.md),
[`oauth_db_token()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_token.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Microsoft client configured with services = "kql":
callback <- oauth_db_fabric(auth$connection, service = "kql")
output$rows <- shiny::renderTable({
  fabricQueryR::fabric_kql_query(
    cluster = "https://example.kusto.fabric.microsoft.com",
    database = "Events",
    query = "Events | take 20",
    token = callback()
  )
})
} # }
```
