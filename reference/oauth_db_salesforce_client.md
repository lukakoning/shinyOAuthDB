# Set up Salesforce sign-in

Set up Salesforce sign-in for a Shiny app that queries CRM records, Data
Cloud or both. Pass the client to shinyOAuth's UI and server modules.
Visitors sign in with their own Salesforce account and keep their
existing data permissions.

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

Register an External Client App with the authorization-code flow and
PKCE, which protects the sign-in code. Enable JWT-based access tokens
for named users; this format works with shinyOAuth's token validation.
The default client discovers sign-in settings from `login_url` over
HTTPS.

shinyOAuth manages token renewal. If Salesforce omits the token's
expiry, shinyOAuth warns and uses its configured fallback lifetime. Your
app's registration and users still need the relevant API and data
permissions.

## See also

[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md).
[`vignette("salesforce", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/salesforce.md)
has registration steps and a complete app.
