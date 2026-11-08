# Set up Google sign-in for BigQuery

Create a sign-in client for a Shiny app that queries BigQuery. Pass it
to shinyOAuth's UI and server modules, then query with
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md).

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

Register a Web OAuth client in Google Cloud. Users need access to the
query project and datasets.

## See also

[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md).
[`vignette("bigquery", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.md)
has sign-in setup and a complete app.

Other sign-in configuration:
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md),
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)

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
