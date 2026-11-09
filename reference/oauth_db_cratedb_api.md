# Query CrateDB as the signed-in user

Query CrateDB data using the signed-in visitor's database privileges.
CrateDB checks their access token and matches it to a database user. The
client sends SQL over HTTPS and returns data frames.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  HTTPS SQL endpoint, including `/_sql` and any proxy prefix.

- schema:

  Default schema, or `NULL` for CrateDB's `doc` default.

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
  or the complete result with metadata when `raw = TRUE`.

- `$execute(sql, parameters = list())` runs a statement and invisibly
  returns its affected row count (`-1` when unknown).

## Details

Configure CrateDB's HTTP JWT authentication and a database user matching
the token's `iss`, `username` and `aud` claims. The CrateDB vignette
explains the provider requirements.

Create the client inside `server()` and call its methods from render or
reactive expressions. Each request uses a current token and discards
results after sign-out or account changes. SQL doesn't retry
automatically. A submitted query can continue after a timeout; check a
failed write's outcome before resubmitting it.

## Parameters and results

Use `$1`, `$2`, ... or `?` placeholders with an unnamed list of values
in `parameters`. Values travel separately from SQL. Scalars, missing
values, arrays and named-list objects are supported. Dates and
timestamps become ISO strings; cast the placeholders to the SQL type you
need. For exact large integers or decimals, use strings and SQL casts.
Numeric parameters must be finite.

BIGINT and NUMERIC results stay as strings. Smaller numbers become R
numeric values and booleans become logical. Dates and timestamps use
epoch-millisecond strings; complex types use list columns with numbers
preserved as strings. Empty results keep their column types.

`raw = TRUE` returns metadata and rows, with numeric row values kept as
strings. HTTP errors report the status without exposing server messages
or credentials.

## See also

[`vignette("cratedb", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.md).
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
runs a local CrateDB and Keycloak example.

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
