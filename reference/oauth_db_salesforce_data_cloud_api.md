# Query Salesforce Data Cloud as the signed-in user

Run Data Cloud (Data 360) SQL through Salesforce's Query Connect API. It
uses the visitor's Salesforce access token and org permissions.

## Usage

``` r
oauth_db_salesforce_data_cloud_api(
  authorization,
  instance_url,
  api_version = "64.0",
  dataspace = "default",
  target = NULL,
  required_scopes = c("api", "cdp_query_api"),
  min_valid_for = 60,
  timeout = 300,
  page_size = 10000L,
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

- dataspace:

  Data Cloud data space API name, default `"default"`.

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

- page_size:

  Maximum number of rows requested per response.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with a `$query(sql, parameters = list(), raw = FALSE)`
method. It submits SQL, polls for completion, fetches all pages, and
returns a data frame. `raw = TRUE` returns combined `data`, `metadata`,
`status` and `returnedRows`.

## Details

Use
[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md)
with `data_cloud = TRUE`. Users need Data Cloud licensing, data-space
access and query permissions. The client uses
`/services/data/v64.0/ssot/query-sql` by default, through the Salesforce
org endpoint. It does not use legacy Query V1/V2 or exchange/store a
second Data Cloud token. API version 64.0 or later is required.

`parameters` is an unnamed list of native SQL parameter descriptors,
each with `name`, `type` and `value` strings. For example,
`list(list(name = "since", type = "date", value = "2026-01-01"))` binds
`:since`. Values are sent separately from SQL. Use Salesforce's SQL type
names; the service validates whether a type and value are supported.

BIGINT and NUMERIC values remain strings to preserve precision. Other
numeric columns become R numeric values, booleans become logical, and
date/time values remain strings. Nested and unknown types remain list
columns. Raw results retain numeric lexemes as strings.

Create the client inside `server()`. Each query pins its starting
authorization and obtains a current token before submission, polling and
result fetching. Results arriving after sign-out, account changes or
lost scopes are discarded. A GET can renew and retry once after HTTP
401. SQL submission is never replayed, including after HTTP 401.
`timeout` covers submission, polling and every result page. A timed-out
or abandoned query may continue on Salesforce; this client does not
cancel remote jobs. Queries run synchronously in R and collect their
results in memory.

## See also

[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md),
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md).
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
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
cloud <- oauth_db_salesforce_data_cloud_api(
  auth$connection, "https://example.my.salesforce.com"
)
output$rows <- shiny::renderTable({
  cloud$query("SELECT ssot__Id__c FROM ssot__Individual__dlm LIMIT 20")
})
} # }
```
