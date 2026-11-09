# Set up Databricks OAuth sign-in

Set up sign-in for a Shiny app that uses a Databricks workspace. Pass
this client to shinyOAuth's UI and server modules, then query with
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md)
or
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).
Each visitor uses their own Databricks account and data permissions.

## Usage

``` r
oauth_db_databricks_client(
  host,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  provider = .odb_databricks_provider(host, client_secret),
  scopes = c("openid", "profile", "email", "offline_access", "all-apis")
)
```

## Arguments

- host:

  Workspace hostname or HTTPS origin. Ignored when `provider` is
  supplied.

- client_id:

  Application ID from the OAuth registration.

- redirect_uri:

  Registered URL where the browser returns after sign-in.

- client_secret:

  Client secret, or `NULL` for a public client.

- ...:

  Other arguments for `shinyOAuth::oauth_client()`.

- provider:

  Custom shinyOAuth provider, replacing the default.

- scopes:

  OAuth scopes to request, replacing the defaults.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

Register your app and its exact redirect URI with Databricks. The
defaults request `all-apis` and refresh access; use `scopes` to replace
them. Omit `client_secret` for a public registration without a secret.

For Azure Databricks using Microsoft Entra tokens, use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "databricks_entra"`.

## See also

[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
client <- oauth_db_databricks_client(
  host = "example.cloud.databricks.com",
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
} # }
```
