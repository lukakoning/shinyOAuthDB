# Set up Snowflake OAuth sign-in

Set up sign-in for a Shiny app using Snowflake's own OAuth integration.
Visitors use their Snowflake account and a role they can access. Pass
this client to shinyOAuth's UI and server modules, then connect with
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md).

## Usage

``` r
oauth_db_snowflake_client(
  server,
  client_id,
  client_secret,
  redirect_uri,
  role,
  ...,
  provider = oauth_db_snowflake_provider(server),
  scopes = c(paste0("session:role:", role), "refresh_token")
)
```

## Arguments

- server:

  Snowflake account hostname. Ignored when `provider` is supplied.

- client_id:

  Application ID from the OAuth registration.

- client_secret:

  Client secret from the Snowflake OAuth integration.

- redirect_uri:

  Registered URL where the browser returns after sign-in.

- role:

  Requested Snowflake role. Ignored when `scopes` is supplied.

- ...:

  Other arguments for `shinyOAuth::oauth_client()`.

- provider:

  Custom shinyOAuth provider, replacing the default.

- scopes:

  OAuth scopes to request, replacing the defaults.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

Register the app's exact redirect URI in a Snowflake custom OAuth
integration. The requested role must match the role used by
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md).
If your account uses an external provider such as Entra or Okta,
configure a shinyOAuth client for that provider instead.

## See also

[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md).
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
client <- oauth_db_snowflake_client(
  server = "organization-account.snowflakecomputing.com",
  role = "REPORTING_READER",
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
} # }
```
