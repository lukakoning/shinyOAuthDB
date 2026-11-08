# Query OpenSearch as the signed-in user

Search documents, run aggregations or use the SQL plugin with the
visitor's current OAuth access token. Results retain OpenSearch's native
JSON structure.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- url:

  HTTPS OpenSearch cluster base URL, including a proxy path if needed.

- target:

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- timeout:

  Maximum seconds for one HTTP operation, including a read retry.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with these methods:

- `$search(index = NULL, body = list(), query = list(), raw = FALSE)`
  posts a Query DSL object to `/<index>/_search`. An index may be a
  name, pattern or character vector. `NULL` uses cluster-wide search.

- `$sql(sql, parameters = list(), raw = FALSE)` posts SQL to
  `/_plugins/_sql`, returning its native JDBC-format JSON response.
  Parameters are an unnamed list of `list(type = "integer", value = 30)`
  descriptors for positional `?` placeholders.

- `$request(path, method = "GET", query = list(), body = NULL, raw = FALSE)`
  sends a native JSON request. Supply relative path segments, for
  example `c("orders", "_doc", "42")`.

## Details

Configure OpenSearch's Security plugin to accept your provider's JWT
access tokens using OpenID Connect or JWT authentication. It must
validate the issuer and audience and map the token's subject and backend
roles to OpenSearch permissions. A Dashboards browser login alone is
insufficient. This client uses bearer tokens, not AWS SigV4 or a shared
service account.

Create the client in `server()`. Each operation obtains a current token,
pins its authorization, and discards responses after account changes,
sign-out or lost permissions. GET and HEAD retry once after HTTP 401.
POST, PUT, PATCH and DELETE are never replayed automatically, including
searches and SQL queries. shinyOAuth renews tokens before requests.

JSON objects become named lists, arrays become lists, and large integers
remain strings. Search hits, aggregations, totals and SQL schema
metadata are preserved rather than flattened into a data frame.
`raw = TRUE` returns an httr2 response. Searches that time out or report
failed shards raise an error unless `raw = TRUE`; use `$request()` for
filtered responses.

SQL requires the server's SQL plugin. There is no automatic pagination:
search pages use native `from`/`size` or `search_after` in the body.
Advanced SQL cursors and other JSON APIs are available through
`$request()`; consume or close cursors before changing accounts. Bulk
NDJSON requests are outside this client's JSON interface.

## See also

[`vignette("opensearch", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.md).
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local OpenSearch and Keycloak example.

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

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
