# Query Supabase as the signed-in user

Read tables and views, call database functions, or send native Data API
requests with the visitor's access token. Supabase applies the
database's grants and row-level security policies.

## Usage

``` r
oauth_db_supabase_api(
  authorization,
  url,
  api_key,
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

  HTTPS Supabase project base URL, without `/rest/v1` or `/auth/v1`.
  Custom domains and reverse proxy paths are supported.

- api_key:

  Project publishable key (`sb_publishable_...`) or legacy `anon` JWT.
  Secret and `service_role` keys are rejected.

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

An R6 client with the same `select()`, `rpc()`, and `request()` methods
as
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md).
`select()` returns a data frame; `rpc()` and `request()` return the
parsed JSON value, or an httr2 response with `raw = TRUE`.

## Details

Create the client inside `server()`. Each request sends the project key
in `apikey` and the visitor's current access token in `Authorization`.
The project key is never used as a substitute for a missing user token.
No database password or PostgreSQL driver is needed.

Use
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)
with Supabase's OAuth server, or supply an authorization from a
third-party provider trusted by the project. OAuth scopes do not grant
table access; configure database grants and RLS. This helper accesses
the REST Data API, not SQL connections, Storage, Realtime, or the
Management API.

The underlying PostgREST client obtains a current token for each
operation, discards responses after account changes or sign-out, and
retries GET/HEAD once after HTTP 401. Writes and POST function calls are
never replayed. Verified HTTPS is required, including for self-hosted
deployments.

## See also

[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md).
[`vignette("supabase", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/supabase.md)
has setup instructions and a complete Shiny app.

Other platform API clients:
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md),
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
supabase <- oauth_db_supabase_api(auth$connection,
  url = Sys.getenv("OAUTHDB_SUPABASE_URL"),
  api_key = Sys.getenv("OAUTHDB_SUPABASE_KEY"))
output$rows <- shiny::renderTable({
  supabase$select("orders", order = "id.asc", limit = 20L)
})
} # }
```
