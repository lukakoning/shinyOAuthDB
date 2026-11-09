# Get a token callback for one Fabric service

Call a fabricQueryR function with the visitor's credentials for one
Fabric service. This helper supplies a token callback: a function
fabricQueryR calls when it needs a current access token. Use
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md)
when working with several services or resource objects such as
Lakehouses.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

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

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function, such as `callback`. Calling `callback()` returns
the token callback to pass to a fabricQueryR function, as
`token = callback()` in the example below.

## Details

Create the helper inside `server()`. Configure
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
for the selected service first. shinyOAuth obtains or renews tokens when
the callback needs them. Keep the callback in the Shiny session that
created it.

## See also

[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md).
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
has sign-in setup and a complete app.

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
