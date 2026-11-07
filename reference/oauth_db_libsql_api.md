# Query libSQL as the signed-in user

Run SQLite SQL against a remote libSQL or compatible Turso endpoint
using the visitor's current access token. Results are returned as data
frames.

## Usage

``` r
oauth_db_libsql_api(
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

  HTTPS database base URL, or a `libsql://` URL (uses HTTPS). A reverse
  proxy path is allowed; omit `/v2/pipeline`.

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
  or a validated Hrana statement result with `raw = TRUE`.

- `$execute(sql, parameters = list())` runs one statement and invisibly
  returns its Hrana result, including `affected_row_count` and
  `last_insert_rowid`.

## Details

The server must accept the access token issued to your shinyOAuth
client. Self-hosted libSQL uses Ed25519 signing keys and libSQL
permission claims; arbitrary OIDC access tokens are not interchangeable
with database tokens. Turso Cloud has a separate external-provider JWKS
configuration. See
[`vignette("libsql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.md)
for both configurations.

Each operation obtains a current token and uses a new Hrana HTTP stream,
closing it in the same request. No stream baton or server-provided URL
is reused. Calls cannot share transactions, temporary tables or
connection state. The helper does not provide a DBI connection or
embedded replica.

Create the helper inside `server()` and call its methods in render or
reactive expressions. Results arriving after account changes, permission
loss or sign-out are discarded. Requests use verified HTTPS and never
retry, including after HTTP 401. A submitted statement may continue on
the server after a timeout or sign-out.

## Parameters and results

Supply an unnamed list for `?` parameters or a fully named list for
named parameters such as `:country`. Values are bound separately from
SQL. Character, logical, integer, finite numeric, raw vectors and
`NULL`/`NA` are supported. Use `I("9223372036854775807")` for an exact
signed 64-bit integer; ordinary character values bind as text. Encode
dates as strings.

SQLite integers are returned as strings to preserve all 64 bits.
Floating point values remain numeric, text remains character and blobs
use raw vectors in list columns. Columns with mixed SQLite types remain
lists. All-null or empty columns use logical missing values;
`raw = TRUE` preserves the server's declared column metadata.

## See also

[`vignette("libsql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.md).
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local libSQL and Keycloak example.

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
libsql <- oauth_db_libsql_api(auth$connection, "https://sqlite.example.org")
output$rows <- shiny::renderTable({
  libsql$query("SELECT id, total FROM orders WHERE country = :country LIMIT 20",
    parameters = list(country = "NL"))
})
} # }
```
