# Query ClickHouse as the signed-in user

Run SQL over ClickHouse's HTTPS interface with the visitor's current
bearer token. Query results are returned as data frames.

## Usage

``` r
oauth_db_clickhouse_api(
  authorization,
  url,
  database = NULL,
  target = NULL,
  required_scopes = character(),
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

- url:

  HTTPS query endpoint, including its port and proxy path if needed.

- database:

  Default database, or `NULL` for the user's server default.

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

  Maximum seconds for one HTTP operation.

- ca_bundle:

  Optional trusted CA certificate bundle path.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with these methods:

- `$query(sql, parameters = list(), raw = FALSE)` returns a data frame,
  or the parsed JSONCompact response when `raw = TRUE`.

- `$execute(sql, parameters = list())` runs a statement without
  collecting a result and invisibly returns its httr2 response.

## Details

The endpoint must accept externally issued bearer tokens. Custom
identity providers currently require ClickHouse Cloud Enterprise,
service version 26.4 or later (26.8 for EC signing keys). This helper
does not use Cloud management API keys, database passwords, or a service
account.

Configure a shinyOAuth client for the provider and audience trusted by
your ClickHouse service. Create the API client inside `server()` and
call its methods from render or reactive expressions. Tokens are
obtained for each request, and a result is discarded if its
authorization changes.

SQL is sent as the POST body. Requests are never replayed automatically,
including HTTP 401, because a submitted statement may have changed data.
Token renewal before each request is handled by shinyOAuth. A timeout or
sign-out stops local access; a submitted query may continue on the
server.

## Parameters

Use native typed placeholders, such as `{country:String}` or
`{id:UInt64}`, with a named list of scalar R values in `parameters`.
Values are sent separately through the HTTP `param_` mechanism.
Character, logical, integer, numeric, `Date`, `POSIXct`, and missing
values are supported. Use character values for exact large integers and
decimals.

`POSIXct` values are formatted as UTC wall-clock strings, regardless of
their R display timezone. Use `DateTime('UTC')` for whole seconds or
`DateTime64(6, 'UTC')` for fractional seconds. Always specify UTC in the
placeholder: an unqualified type uses the server or session timezone,
and another timezone annotation changes the instant represented by the
formatted string. Timestamp encoding retains up to six fractional
digits.

For arrays, tuples, or already encoded values, wrap native ClickHouse
escaped-format strings in [`I()`](https://rdrr.io/r/base/AsIs.html) to
preserve their encoding.

## Result types

Signed and unsigned integers of 64 bits or more, and decimals, remain
strings. Smaller integers and floats become R numbers; Bool becomes
logical and Date/Date32 become `Date`. Timestamps keep their server
string representation. Arrays, maps, tuples, JSON, and other complex
values stay in list columns. Empty results preserve column metadata.

Omit FORMAT clauses and output-format overrides from SQL. The client
requests JSONCompact with exact numeric quoting and validates the entire
response before returning any rows. `raw = TRUE` preserves metadata and
statistics, with JSON arrays decoded as R lists.

## See also

[`vignette("clickhouse", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.md).

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
clickhouse <- oauth_db_clickhouse_api(auth$connection,
  url = "https://example.clickhouse.cloud:8443", database = "reporting")
output$rows <- shiny::renderTable({
  clickhouse$query("SELECT id, total FROM orders WHERE country = {country:String} LIMIT 20",
    parameters = list(country = "NL"))
})
} # }
```
