# Query Salesforce CRM as the signed-in user

Read Salesforce CRM records using the visitor's object, field and record
permissions. CRM objects, such as accounts, are queried with
Salesforce's query language, SOQL. Queries return data frames for your
Shiny app.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- instance_url:

  Trusted HTTPS origin of your Salesforce org, such as
  `"https://example.my.salesforce.com"`. Use the org URL, not a
  Lightning URL.

- api_version:

  Salesforce REST API version without `v`, default `"64.0"`.

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

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$query(soql, include_deleted = FALSE, raw = FALSE)` fetches all
  result pages and returns a data frame. `include_deleted = TRUE`
  includes deleted or archived records through QueryAll. `raw = TRUE`
  returns combined native records and `totalSize`, including the count
  for `SELECT COUNT()`.

- `$objects()` returns the API's object catalog.

- `$describe(object)` returns field definitions and other object
  metadata.

## Details

Use
[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md)
for sign-in. Create this API client inside `server()` and call its
methods from render or reactive expressions. The client gets a current
token for each request and discards results after sign-out or account
changes. GET requests can refresh and retry once after HTTP 401.

Queries fetch all result pages into R memory. `timeout` applies to the
whole operation. Relationships and child-query results stay in list
columns; ordinary numbers become R numeric values and large integers
stay as strings. Empty results have no field metadata; use `$describe()`
for field types.

Supply SOQL as written. This client doesn't bind SQL parameters or
provide a DBI connection. Use `raw = TRUE` for the records and metadata
without conversion to a data frame.

## See also

[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md).
[`vignette("salesforce", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.md).

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
