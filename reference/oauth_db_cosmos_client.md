# Set up Microsoft sign-in for Azure Cosmos DB

Create a Microsoft Entra client for a Shiny app that reads Azure Cosmos
DB for NoSQL with each visitor's account. Pass it to shinyOAuth's UI and
server modules, then use
[`oauth_db_cosmos_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cosmos_api.md)
inside `server()`.

## Usage

``` r
oauth_db_cosmos_client(
  tenant_id,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  resource = "https://cosmos.azure.com",
  provider = shinyOAuth::oauth_provider_microsoft(tenant = tenant_id, id_token_validation
    = TRUE, userinfo_required = FALSE),
  scopes = c("openid", "profile", "offline_access", paste0(resource, "/.default")),
  token_targets = list(cosmos = list(resource = resource, scopes = paste0(resource,
    "/.default"), required_scopes = character())),
  token_target_default = "cosmos"
)
```

## Arguments

- tenant_id:

  Microsoft Entra tenant ID. Ignored when `provider` is supplied.

- client_id:

  Application ID from the OAuth registration.

- redirect_uri:

  Registered URL where the browser returns after sign-in.

- client_secret:

  Client secret, or `NULL` for a public client.

- ...:

  Other arguments for `shinyOAuth::oauth_client()`.

- resource:

  Cosmos DB token audience, default `"https://cosmos.azure.com"`. Change
  this with `provider` for another Azure cloud or an account-specific
  audience accepted by your deployment.

- provider:

  Custom shinyOAuth provider, replacing the default.

- scopes:

  OAuth consent scopes, replacing the defaults.

- token_targets:

  Named token targets, replacing the Cosmos DB default.

- token_target_default:

  Default token target name.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

Use your own Microsoft Entra Web application registration with the exact
redirect URI. The preset requests the resource's `.default` scope and
keeps its token in the `"cosmos"` target. `.default` is a consent
marker, not an operation permission checked by the database helper.

Cosmos DB doesn't publish a delegated permission in the app-registration
permission picker. Validate that your tenant and registration permit a
user token for this resource before deploying. Sign-in configuration and
Cosmos DB data-plane role assignments are separate requirements. The
preset doesn't use Azure CLI, managed identity or account keys.

## See also

[`oauth_db_cosmos_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cosmos_api.md).
[`vignette("cosmos", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cosmos.md)
has setup steps and a complete app.
