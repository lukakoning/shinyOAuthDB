# Query libSQL as the signed-in user

Run SQLite SQL on a remote libSQL or compatible Turso database using
each visitor's access token. The database checks the token's
permissions, and the client returns data frames. No R database driver is
needed.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  HTTPS database base URL, or a `libsql://` URL (uses HTTPS). A reverse
  proxy path is allowed; omit `/v2/pipeline`.

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
  or the server's rows and metadata with `raw = TRUE`.

- `$execute(sql, parameters = list())` runs one statement and invisibly
  returns metadata, including `affected_row_count` and
  `last_insert_rowid`.

## Details

The database must accept tokens from your shinyOAuth client. Self-hosted
libSQL needs a particular signing key and permission format; Turso Cloud
has its own external-provider setup. The libSQL vignette explains both.

Create the client inside `server()` and call its methods from render or
reactive expressions. Each call gets a current token and runs one
statement in its own request. Calls don't share transactions or
temporary tables; separate `BEGIN` and `COMMIT` calls can't form a
transaction.

Results are discarded after sign-out or account changes. SQL requests
don't retry automatically. A submitted statement can finish after a
timeout or sign-out, so check a failed write before submitting it again.

## Parameters and results

Use an unnamed list for `?` parameters or a named list for placeholders
such as `:country`. Values are bound separately from SQL. Character,
logical, integer, finite numeric, raw vectors and `NULL`/`NA` are
supported. Use `I("9223372036854775807")` for an exact signed 64-bit
integer; ordinary strings bind as text. Format dates and timestamps as
database strings.

SQLite integers return as strings to preserve all 64 bits.
Floating-point values stay numeric, with non-finite results represented
as `NaN`. Blobs use raw vectors in list columns, and columns with mixed
types remain lists. Use `raw = TRUE` for the server's statement metadata
and rows.

## See also

[`vignette("libsql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/libsql.md).
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local libSQL and Keycloak example.

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
