# Set up Supabase OAuth sign-in

Create a sign-in client for a Supabase project with its OAuth 2.1 server
enabled. Pass it to shinyOAuth's UI and server modules, then query with
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md).

## Usage

``` r
oauth_db_supabase_client(
  url,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  provider = .odb_supabase_provider(url, client_secret),
  scopes = c("openid", "profile", "email")
)
```

## Arguments

- url:

  Supabase project base URL. Ignored when `provider` is supplied.

- client_id:

  Application ID from the OAuth registration.

- redirect_uri:

  Registered URL where the browser returns after sign-in.

- client_secret:

  Client secret, or `NULL` for a public client.

- ...:

  Other arguments for `shinyOAuth::oauth_client()`.

- provider:

  A custom shinyOAuth provider, replacing Supabase discovery.

- scopes:

  Identity scopes to request. The defaults request `openid`, `profile`,
  and `email`; these do not grant database permissions.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

Enable Supabase's OAuth server, configure its sign-in and consent UI,
and register the app's exact redirect URI. Use asymmetric JWT signing
keys for OIDC. The default provider makes an HTTPS OIDC discovery
request to the project's `/auth/v1` issuer and enables PKCE and nonce
validation.

A nonempty secret selects HTTP Basic client authentication; without one,
the preset uses a public client. Supabase returns refresh tokens without
an `offline_access` scope. shinyOAuth handles renewal.

For a third-party provider configured in Supabase, pass its provider
here or use an ordinary `shinyOAuth::oauth_client()`.

## See also

[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md).
[`vignette("supabase", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/supabase.md).

Other sign-in configuration:
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md)

## Examples

``` r
if (FALSE) { # \dontrun{
client <- oauth_db_supabase_client(
  url = Sys.getenv("OAUTHDB_SUPABASE_URL"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
} # }
```
