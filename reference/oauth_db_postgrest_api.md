# Query PostgREST as the signed-in user

Read PostgreSQL tables or call database functions over a web API using
each visitor's account. PostgREST checks their access token, and
PostgreSQL grants and row policies determine which data they can access.
No PostgreSQL driver is needed in R.

## Usage

``` r
oauth_db_postgrest_api(
  authorization,
  url,
  schema = NULL,
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

  HTTPS PostgREST base URL, including a reverse proxy path if needed.

- schema:

  Exposed PostgreSQL schema, or `NULL` for the server default.

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

  Maximum seconds for one request, including its refresh retry.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$select(table, select = "*", filters = list(), order = NULL, limit = NULL, offset = NULL, count = NULL, raw = FALSE)`
  reads one result page as a data frame. Filters use PostgREST
  expressions, for example `list(country = "eq.NL")`.

- `$rpc(name, args = list(), raw = FALSE)` calls an exposed database
  function with POST and returns its parsed JSON value.

- `$request(path, method = "GET", query = list(), body = NULL, prefer = NULL, raw = FALSE)`
  sends a native PostgREST request. Supply path segments such as
  `c("rpc", "my_function")`.

## Details

Configure a shinyOAuth client for the provider trusted by PostgREST. Its
access token must have the audience and role claims the server expects.
PostgreSQL grants and row policies control data access.

Create the client inside `server()` and call its methods from render or
reactive expressions. Requests get a current token and discard results
after sign-out or account changes. GET and HEAD can refresh and retry
once after HTTP 401; writes and POST function calls don't retry.

## Results and pagination

`select()` returns one page, which the server can limit further. Use
`limit`, `offset` and a stable `order` to fetch more. Set `count` to
`"exact"`, `"planned"` or `"estimated"` to request a total.

Use `raw = TRUE` for an httr2 response and inspect its Content-Range
with
[`httr2::resp_header()`](https://httr2.r-lib.org/reference/resp_headers.html).
Otherwise selections return data frames, with large integers preserved
as strings. Embedded resources can produce nested data frames or list
columns. Empty selections have no column metadata. Dates and decimal
strings keep their JSON representation.

## Local demo

The services-only PostgREST demo allows its exact local HTTP endpoint
while the demo handle is active. All other endpoints require HTTPS.
Stopping the demo removes that exception for existing clients too.

## See also

[`vignette("postgrest", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.md).

## Examples

``` r
if (FALSE) { # \dontrun{
postgrest <- oauth_db_postgrest_api(auth$connection,
  url = "https://data.example.org", schema = "reporting")
output$rows <- shiny::renderTable({
  postgrest$select("orders", filters = list(country = "eq.NL"),
    order = "id.asc", limit = 20L)
})
} # }
```
