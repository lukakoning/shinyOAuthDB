# Query Salesforce Data Cloud as the signed-in user

Run Salesforce Data Cloud SQL with the visitor's Salesforce account and
data permissions. The client uses Query Connect API and returns data
frames. It can share a sign-in with
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md).

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- instance_url:

  Trusted HTTPS origin of your Salesforce org, such as
  `"https://example.my.salesforce.com"`. Use the org URL, not a
  Lightning URL.

- api_version:

  Salesforce REST API version without `v`, default `"64.0"`.

- dataspace:

  Data Cloud data space API name, default `"default"`.

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

  Total seconds allowed for an operation, including polling, result
  pages and any permitted refresh retry.

- page_size:

  Maximum number of rows requested per response.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with a `$query(sql, parameters = list(), raw = FALSE)`
method. It waits for completion, fetches all pages, and returns a data
frame. `raw = TRUE` returns combined `data`, `metadata`, `status` and
`returnedRows`.

## Details

Use
[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md)
with `data_cloud = TRUE`. Users need Data Cloud licensing, access to the
data space and query permissions. The client uses your Salesforce org
endpoint and API version 64.0 or later.

Create the client inside `server()` and call `$query()` from a render or
reactive expression. Each request gets a current token and discards
results after sign-out or account changes.

## Parameters and results

Use an unnamed list of SQL parameter descriptors with `name`, `type` and
`value` strings. For example,
`list(list(name = "since", type = "date", value = "2026-01-01"))` binds
`:since`. Values travel separately from SQL; use the types Salesforce
accepts.

BIGINT and NUMERIC results stay as strings to preserve precision. Other
numbers become R numeric values and booleans become logical. Dates and
times stay as strings; nested and unknown types use list columns. Use
`raw = TRUE` for rows, metadata and final query status.

## Longer queries

Queries wait for completion and collect all pages in R memory. `timeout`
covers submission, polling and fetching. A timeout or sign-out doesn't
cancel a submitted query.

GET requests can refresh and retry once after HTTP 401. SQL submission
doesn't retry automatically, so check Salesforce after a submission
failure before running the query again.

## See also

[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md),
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md).
[`vignette("salesforce", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.md).

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
