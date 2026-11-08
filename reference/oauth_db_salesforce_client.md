# Set up Salesforce sign-in

Create a client for Salesforce CRM and, optionally, Data Cloud (Data
360). Register an External Client App with the authorization-code flow
and PKCE.

## Usage

``` r
oauth_db_salesforce_client(
  client_id,
  redirect_uri,
  client_secret,
  ...,
  login_url = "https://login.salesforce.com",
  data_cloud = FALSE,
  provider = shinyOAuth::oauth_provider_oidc_discover(.odb_salesforce_origin(login_url)),
  scopes = c("openid", "profile", "api", "refresh_token", if (data_cloud)
    "cdp_query_api")
)
```

## Arguments

- client_id:

  Application ID from the OAuth registration.

- redirect_uri:

  Registered URL where the browser returns after sign-in.

- client_secret:

  Client secret from the Salesforce registration. Pass `NULL` only with
  a custom public-client provider matching that registration.

- ...:

  Other arguments for `shinyOAuth::oauth_client()`.

- login_url:

  Salesforce login origin: your My Domain URL,
  `"https://login.salesforce.com"`, or `"https://test.salesforce.com"`.

- data_cloud:

  Include the `cdp_query_api` consent scope.

- provider:

  Custom shinyOAuth provider, replacing OIDC discovery.

- scopes:

  OAuth scopes, replacing the defaults.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

The default provider is discovered from `login_url` over HTTPS.
Discovery configures signed ID-token validation, user information and
PKCE. A custom provider replaces discovery. `shinyOAuth` manages tokens
and renewal.

Enable Salesforce's JWT-based access tokens for named users in the app
registration. Legacy opaque Salesforce session tokens containing `!` are
not accepted by shinyOAuth's bearer-token validation.

Salesforce can omit access-token expiry. In that case shinyOAuth warns
and applies its configured fallback lifetime. GET requests can renew a
rejected token once; SQL submissions are never replayed.

## See also

[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md).
[`vignette("salesforce", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.md)
has registration steps and a complete app.

Other sign-in configuration:
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md),
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)
