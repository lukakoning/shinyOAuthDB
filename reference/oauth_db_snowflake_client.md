# Set up Snowflake OAuth sign-in

Create a sign-in client for Snowflake's own OAuth integration and a role
your app's users can access. Pass it to shinyOAuth's UI and server
modules, then connect with
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

Register the app's redirect URI in the Snowflake OAuth integration. For
External OAuth through Entra, Okta, or another provider, use that
provider's shinyOAuth client configuration.

## See also

[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md).
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
has sign-in setup and a complete app.

Other sign-in configuration:
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md),
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)

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
