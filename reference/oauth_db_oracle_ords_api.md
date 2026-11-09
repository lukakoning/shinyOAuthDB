# Access Oracle REST resources as the signed-in user

Read Oracle data through Oracle REST Data Services (ORDS) using each
visitor's access token. ORDS exposes tables and custom database handlers
as web APIs. This client calls those APIs over HTTPS without Oracle
client libraries.

## Usage

``` r
oauth_db_oracle_ords_api(
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

  HTTPS ORDS schema base URL, including any proxy prefix, for example
  `"https://data.example.org/ords/reporting"`.

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

- `$select(resource, query = list(), raw = FALSE)` reads one page of
  records from an AutoREST collection. Pass query parameters such as
  `list(limit = 20L, offset = 0L)`.

- `$request(path, method = "GET", query = list(), body = NULL, raw = FALSE, trailing_slash = FALSE)`
  calls a JSON resource. Supply relative path segments, for example
  `c("api", "sales")`. Set `trailing_slash = TRUE` when the resource URL
  ends in `/`.

## Details

Configure ORDS to trust your provider's JWT access tokens and map their
scopes or roles to resource privileges. Create the client inside
`server()` and call its methods from render or reactive expressions.

ORDS controls access to its endpoints. The token's user ID is available
to handlers as `:current_user`, but it doesn't automatically change the
Oracle database schema. Configure handler filtering or a database
security context to apply the required per-user data access.

Results are JSON lists, including `items`, `hasMore` and pagination
links. Large integers stay as strings. Fetch pages explicitly; the
client doesn't follow links or redirects. `raw = TRUE` and HEAD return
an httr2 response; successful empty responses otherwise return invisible
`NULL`.

Requests use a current token and discard results after sign-out or
account changes. GET and HEAD can refresh and retry once after HTTP 401;
writes don't retry automatically.

## See also

[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md),
[`vignette("oracle-ords", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle-ords.md).

## Examples

``` r
if (FALSE) { # \dontrun{
ords <- oauth_db_oracle_ords_api(
  auth$connection, "https://data.example.org/ords/reporting"
)
output$rows <- shiny::renderPrint({
  ords$select("orders", query = list(limit = 20L))$items
})
} # }
```
