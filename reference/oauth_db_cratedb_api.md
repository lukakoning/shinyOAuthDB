# Query CrateDB as the signed-in user

Run SQL through CrateDB's HTTPS interface using the visitor's current
JWT access token. CrateDB validates the token, maps it to a database
user and enforces that user's privileges.

## Usage

``` r
oauth_db_cratedb_api(
  authorization,
  url,
  schema = NULL,
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

  HTTPS SQL endpoint, including `/_sql` and any proxy prefix.

- schema:

  Default schema, or `NULL` for CrateDB's `doc` default.

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
  or the complete result with metadata when `raw = TRUE`.

- `$execute(sql, parameters = list())` runs a statement and invisibly
  returns its affected row count (`-1` when unknown).

## Details

Configure CrateDB's JWT authentication for HTTP and a database user
whose JWT properties match the token's `iss`, `username` and `aud`
claims. The provider must issue a compatible access token; an ordinary
browser login or an ID token does not establish database access.

Create this client inside `server()`. shinyOAuth obtains or renews a
token before each request. Account changes, missing permissions,
sign-out and session end stop local access; results arriving after an
authorization change are discarded. SQL submissions are never retried,
including 401 responses, because even a query can have side effects. A
timed-out query may continue on the server.

## Parameters and results

Use `$1`, `$2`, ... or `?` placeholders with an unnamed list of
positional `parameters`. Values are sent separately in CrateDB's JSON
`args` array. Scalars, missing values, arrays and named-list objects are
supported. Dates and timestamps become ISO strings; cast their
placeholders to the desired SQL type. Use strings and SQL casts for
exact large integers and decimals. Non-finite numeric parameters are
rejected.

BIGINT and NUMERIC columns are character vectors, preserving every
digit. Smaller integers and floating-point values become R numbers,
booleans become logical, and text becomes character. Timestamps and
dates retain their epoch-millisecond strings. Arrays, objects and other
complex types remain list columns, with JSON numbers preserved as
strings. Empty results keep their column types and duplicate column
names are preserved.

`raw = TRUE` returns metadata and rows, preserving numeric values within
rows as strings. HTTP failures expose the HTTP status without including
server messages, SQL text or credentials.

## See also

[`vignette("cratedb", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.md).
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local CrateDB and Keycloak example.

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
crate <- oauth_db_cratedb_api(auth$connection,
  url = "https://crate.example.org:4200/_sql", schema = "doc")
output$rows <- shiny::renderTable({
  crate$query("SELECT id, total FROM orders WHERE country = $1 LIMIT 20",
    parameters = list("NL"))
})
} # }
```
