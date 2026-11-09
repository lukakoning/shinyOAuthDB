# Query ClickHouse as the signed-in user

Query ClickHouse data using the signed-in visitor's database
permissions. The client sends their access token with SQL requests over
HTTPS and returns data frames. No database driver is needed.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  HTTPS query endpoint, including its port and proxy path if needed.

- database:

  Default database, or `NULL` for the user's server default.

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

  Maximum seconds for one HTTP operation.

- ca_bundle:

  Optional trusted CA certificate bundle path.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$query(sql, parameters = list(), raw = FALSE)` returns a data frame,
  or the parsed server response when `raw = TRUE`.

- `$execute(sql, parameters = list())` runs a statement without
  collecting a result and invisibly returns its httr2 response.

## Details

Configure your service to accept access tokens from the app's sign-in
provider. Custom providers require ClickHouse Cloud Enterprise, service
version 26.4 or later (26.8 for EC signing keys). The ClickHouse
vignette explains the service setup.

Create the client inside `server()` and call its methods from render or
reactive expressions. Each request uses a current token and discards
results after sign-out or account changes. SQL doesn't retry
automatically, since a statement may already have executed. Submitted
work can continue after a timeout or sign-out.

## Parameters

Use typed placeholders such as `{country:String}` or `{id:UInt64}` and a
named list of R values in `parameters`. Values are sent separately from
SQL. Character, logical, integer, numeric, `Date`, `POSIXct` and missing
values are supported. Use strings for exact large integers and decimals.

R timestamps are formatted in UTC. Use `DateTime('UTC')` or
`DateTime64(6, 'UTC')` in the placeholder to preserve the intended
instant, including up to six fractional digits. A different SQL timezone
would interpret the formatted value differently.

For arrays or tuples, wrap ClickHouse escaped-format strings in
[`I()`](https://rdrr.io/r/base/AsIs.html) to preserve their encoding.

## Result types

Integers of 64 bits or more and decimals stay as strings. Smaller
integers and floats become R numbers, booleans become logical, and dates
become `Date`. Timestamps keep their server string format; complex
values use list columns. Empty results preserve column metadata.

Leave FORMAT clauses and output-format overrides out of SQL. Use
`raw = TRUE` for the parsed server response, including metadata and
statistics, with JSON arrays represented as R lists.

## See also

[`vignette("clickhouse", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.md).

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
