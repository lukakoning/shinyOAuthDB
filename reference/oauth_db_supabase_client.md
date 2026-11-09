# Set up Supabase OAuth sign-in

Set up sign-in for people with accounts in a Supabase project. The
project must have its OAuth server enabled. Pass this client to
shinyOAuth's UI and server modules, then read data with
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

Enable the project's OAuth server, configure its sign-in and consent
pages, and register the app's exact redirect URI. Use asymmetric signing
keys so shinyOAuth can validate the sign-in identity.

Supply `client_secret` for a confidential registration; omit it for a
public registration without a secret. Supabase supplies refresh tokens
without an `offline_access` scope, and shinyOAuth handles renewal.

For a third-party provider trusted directly by the project, supply that
`provider` or use `shinyOAuth::oauth_client()`.

## See also

[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md).
[`vignette("supabase", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/supabase.md).

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
