# Access Oracle REST resources as the signed-in user

Read protected Oracle REST Data Services (ORDS) resources and call JSON
handlers using the visitor's OAuth access token. Configure ORDS to trust
the provider's JWTs and map their scopes or roles to ORDS privileges.

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

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- url:

  HTTPS ORDS schema base URL, including any proxy prefix, for example
  `"https://data.example.org/ords/reporting"`.

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

- `$select(resource, query = list(), raw = FALSE)` reads one AutoREST
  collection page. Pass native query parameters such as
  `list(limit = 20L, offset = 0L)`.

- `$request(path, method = "GET", query = list(), body = NULL, raw = FALSE, trailing_slash = FALSE)`
  calls a JSON resource. Supply relative path segments, for example
  `c("api", "sales")`. Set `trailing_slash = TRUE` when the resource URL
  ends in `/`.

## Details

ORDS JWT profiles support external providers including OCI IAM,
Keycloak, Auth0 and Okta when their tokens meet the configured issuer,
audience, signing-key and privilege requirements. Register a browser
authorization code flow in shinyOAuth. An unrelated database or console
access token does not authorize an ORDS resource.

ORDS enforces its resource privileges. A JWT subject is available to
handlers as `:current_user`; it does not automatically switch the
handler to a distinct Oracle database schema. Configure user filtering
or a supported database security context where per-user data access is
needed.

Results retain native JSON lists, including `items`, `hasMore`, offsets
and links. Large JSON integers are strings. The client does not follow
links or redirects; page explicitly with native query parameters.
`raw = TRUE` returns an httr2 response. HEAD also returns the response;
successful empty responses return invisible `NULL` otherwise.

Create the client inside `server()`. Each request obtains a current
token pinned to the selected authorization; late responses after account
changes or sign-out are discarded. GET and HEAD retry once after HTTP
401. Writes are never replayed automatically. No Oracle client libraries
are needed.

## See also

[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md),
[`vignette("oracle-ords", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle-ords.md).

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

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
