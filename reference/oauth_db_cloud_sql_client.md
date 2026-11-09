# Set up Google sign-in for Cloud SQL

Create a Google OAuth client for Cloud SQL IAM database authentication.
Pass it to shinyOAuth's UI and server modules, then create the
PostgreSQL connection helper inside `server()`.

## Usage

``` r
oauth_db_cloud_sql_client(
  client_id,
  redirect_uri,
  client_secret,
  ...,
  provider = shinyOAuth::oauth_provider_google(),
  scopes = c("openid", "email", "https://www.googleapis.com/auth/sqlservice.login")
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

Register a Web OAuth client with the app's exact redirect URI. The
default scopes request identity and Cloud SQL login, without Cloud SQL
administration. Google sign-in and token renewal use shinyOAuth; the
database helper doesn't read Application Default Credentials or start
the Cloud SQL Auth Proxy.

## See also

[`oauth_db_cloud_sql_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_sql_postgres.md).
[`vignette("cloud-sql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-sql.md)
has setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
client <- oauth_db_cloud_sql_client(
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
} # }
```
