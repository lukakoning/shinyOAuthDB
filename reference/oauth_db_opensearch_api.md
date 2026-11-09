# Query OpenSearch as the signed-in user

Search OpenSearch documents and calculate summaries using each visitor's
permissions. An index holds the documents you query. The client supports
JSON searches and the SQL plugin, returning results as R lists.

## Usage

``` r
oauth_db_opensearch_api(
  authorization,
  url,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  HTTPS OpenSearch cluster base URL, including a proxy path if needed.

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

- timeout:

  Maximum seconds for one HTTP operation, including a read retry.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$search(index = NULL, body = list(), query = list(), raw = FALSE)`
  searches an index using an OpenSearch JSON query. The index can be a
  name, pattern or character vector; `NULL` searches across the cluster.

- `$sql(sql, parameters = list(), raw = FALSE)` runs a query through the
  SQL plugin and returns its native JSON result.

- `$request(path, method = "GET", query = list(), body = NULL, raw = FALSE)`
  calls a JSON API. Supply relative path segments, such as
  `c("orders", "_doc", "42")`.

## Details

Configure OpenSearch's Security plugin to accept your provider's tokens
and map the user and role claims to OpenSearch permissions. The endpoint
must accept bearer tokens; AWS SigV4 needs a different client.

Create the client inside `server()` and call its methods from render or
reactive expressions. Each operation uses a current token and discards
results after sign-out or account changes. GET and HEAD can refresh and
retry once after HTTP 401; POST searches, SQL and writes don't retry.

Search results keep `hits`, `aggregations` and totals as R lists. SQL
results keep their `schema` and `datarows`. Large integers stay as
strings. Use `raw = TRUE` for an httr2 response. Searches reporting a
timeout or failed shards raise an error unless you request the raw
response.

## SQL parameters and pagination

SQL requires the server's SQL plugin. Use `?` placeholders with an
unnamed list of typed values, such as
`list(list(type = "integer", value = 30))` in `parameters`.

Fetch search pages explicitly with `from`/`size` or `search_after`. Use
`$request()` for SQL cursors and other JSON APIs; consume or close
cursors before changing accounts.

## See also

[`vignette("opensearch", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.md).
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local OpenSearch and Keycloak example.

## Examples

``` r
if (FALSE) { # \dontrun{
search <- oauth_db_opensearch_api(auth$connection,
  url = "https://search.example.org")
output$results <- shiny::renderPrint({
  search$search("orders", body = list(
    size = 20L, query = list(term = list(country = "NL"))
  ))$hits
})
} # }
```
