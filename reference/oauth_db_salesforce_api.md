# Query Salesforce CRM as the signed-in user

Run SOQL queries and inspect objects through Salesforce's REST API.
Salesforce applies the visitor's object, field and record permissions.

## Usage

``` r
oauth_db_salesforce_api(
  authorization,
  instance_url,
  api_version = "64.0",
  target = NULL,
  required_scopes = "api",
  min_valid_for = 60,
  timeout = 300,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- instance_url:

  Trusted HTTPS origin of your Salesforce org, such as
  `"https://example.my.salesforce.com"`. Use the org URL, not a
  Lightning URL.

- api_version:

  Salesforce REST API version without `v`, default `"64.0"`.

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

  Total seconds allowed for an operation, including polling, result
  pages and any permitted refresh retry.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with these methods:

- `$query(soql, include_deleted = FALSE, raw = FALSE)` fetches all
  result pages and returns a data frame. `include_deleted = TRUE` uses
  QueryAll. `raw = TRUE` returns combined native records and
  `totalSize`, including the count for `SELECT COUNT()`.

- `$objects()` returns the native sObject discovery response.

- `$describe(object)` returns native object metadata.

## Details

Create the client inside `server()`. Each operation pins its starting
authorization and obtains a current access token before each request.
Responses arriving after sign-out, account changes or permission loss
are discarded. A GET can retry once after HTTP 401 with a renewed token.

Pagination accepts only query-locator paths for the configured API
version on the configured org. Redirects are refused. `timeout` covers
all pages of an operation. Results are collected synchronously in R
memory.

Top-level Salesforce `attributes` metadata is omitted from data frames.
Relationships and child queries remain list columns. Ordinary JSON
numbers use R numeric values; large integers remain strings. An empty
result has no column metadata; use `$describe()` when you need field
types. SOQL is supplied as written, without SQL parameter interpolation.

## See also

[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md).
[`vignette("salesforce", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.md).

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
crm <- oauth_db_salesforce_api(
  auth$connection, "https://example.my.salesforce.com"
)
output$rows <- shiny::renderTable({
  crm$query("SELECT Id, Name FROM Account LIMIT 20")
})
} # }
```
