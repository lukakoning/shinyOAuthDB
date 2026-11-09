# Query Supabase as the signed-in user

Read Supabase tables or call database functions using each visitor's
account. The Data API exposes PostgreSQL data over HTTPS, so no database
driver is needed. Database grants and row-level security policies
control which records the user can read or change.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  HTTPS Supabase project base URL, without `/rest/v1` or `/auth/v1`.
  Custom domains and reverse proxy paths are supported.

- api_key:

  Project publishable key (`sb_publishable_...`) or legacy `anon` JWT.
  Secret and `service_role` keys are rejected.

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

A client object with the same `select()`, `rpc()`, and `request()`
methods as
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md).
`select()` returns a data frame; `rpc()` and `request()` return the
parsed JSON value, or an httr2 response with `raw = TRUE`.

## Details

Create the client inside `server()` and call its methods from render or
reactive expressions. Use
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)
for project sign-in, or an authorization from a third-party provider the
project trusts.

The project key identifies the application; the visitor's token supplies
their identity. OAuth scopes don't grant table access, so configure
database grants and row-level security policies too. This client uses
the Data API; use a separate helper for a direct SQL connection.

Requests use a current token and discard results after sign-out or
account changes. GET and HEAD can refresh and retry once after HTTP 401;
writes and POST function calls don't retry automatically. HTTPS is
required, including for self-hosted projects.

## See also

[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md).
[`vignette("supabase", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/supabase.md)
has setup instructions and a complete Shiny app.

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
