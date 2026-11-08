# Query PostgREST as the signed-in user

Read PostgreSQL tables and views or call exposed functions through
PostgREST, using the visitor's current bearer token for each request.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- url:

  HTTPS PostgREST base URL, including a reverse proxy path if needed.

- schema:

  Exposed PostgreSQL schema, or `NULL` for the server default.

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

  Maximum seconds for one request, including its refresh retry.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with these methods:

- `$select(table, select = "*", filters = list(), order = NULL, limit = NULL, offset = NULL, count = NULL, raw = FALSE)`
  reads one result page as a data frame. Filters use PostgREST
  expressions, for example `list(country = "eq.NL")`.

- `$rpc(name, args = list(), raw = FALSE)` calls an exposed database
  function with POST and returns its parsed JSON value.

- `$request(path, method = "GET", query = list(), body = NULL, prefer = NULL, raw = FALSE)`
  sends a native PostgREST request. Supply path segments such as
  `c("rpc", "my_function")`.

## Details

The services-only PostgREST demo permits its exact loopback HTTP
endpoint while the returned demo handle is active. All other endpoints
require HTTPS. Stopping the demo revokes this exception for existing API
clients too.

Configure a shinyOAuth client for the identity provider trusted by your
PostgREST deployment. Its access token must be a JWT with the expected
audience and role claims. PostgREST verifies the token; PostgreSQL
grants and row-level security control which data the visitor can access.

Create the client inside `server()` and call its methods in render or
reactive expressions. No PostgreSQL driver or native OAuth hook is
needed. `schema` uses Accept-Profile for reads and Content-Profile for
writes.

Each call pins its starting authorization, obtains a current access
token, and discards responses after sign-out, account changes, or
permission loss. GET and HEAD retry once after a 401 with a renewed
token. POST, PATCH, PUT, and DELETE are never replayed automatically,
including function calls.

## Results and pagination

`select()` returns one page; the server can cap its size. Use `limit`,
`offset`, and a deterministic `order` to page explicitly. Set `count` to
`"exact"`, `"planned"`, or `"estimated"` to request a total.

`raw = TRUE` returns an httr2 response, including Content-Range; inspect
it with
[`httr2::resp_header()`](https://httr2.r-lib.org/reference/resp_headers.html).
Otherwise JSON is decoded with large integers preserved as strings.
Embedded resources may become nested data frames or list columns. An
empty selection returns a zero-column data frame. Dates and decimal
strings keep the server's JSON representation.

## See also

[`vignette("postgrest", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.md).

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md)

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
