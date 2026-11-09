# Set up Google sign-in for BigQuery

Set up Google sign-in for a Shiny app that queries BigQuery. The client
holds your app registration and requested permissions. Pass it to
shinyOAuth's UI and server modules, then use
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md)
to query with each visitor's Google account.

## Usage

``` r
oauth_db_bigquery_client(
  client_id,
  redirect_uri,
  client_secret,
  ...,
  provider = shinyOAuth::oauth_provider_google(),
  scopes = c("openid", "profile", "email", "https://www.googleapis.com/auth/bigquery")
)
```

## Arguments

- client_id:

  Application ID from the OAuth registration.

- redirect_uri:

  Registered URL where the browser returns after sign-in.

- client_secret:

  Client secret from a Google Web OAuth registration.

- ...:

  Other arguments for `shinyOAuth::oauth_client()`.

- provider:

  Custom shinyOAuth provider, replacing the default.

- scopes:

  OAuth scopes to request, replacing the defaults.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

Register a Web OAuth client in Google Cloud with your app's exact
redirect URI. Create this client outside `server()`; the registration is
shared by the app, while each visitor's sign-in stays in their own
session. Users need access to the query project and datasets.

## See also

[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md).
[`vignette("bigquery", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
client <- oauth_db_bigquery_client(
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
} # }
```
