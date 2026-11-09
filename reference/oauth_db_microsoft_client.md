# Set up Microsoft sign-in for database access

Set up Microsoft sign-in for a Shiny app that queries Azure SQL, Azure
PostgreSQL, Azure MySQL or other supported Microsoft services. Choose
the services your app uses, then pass this client to shinyOAuth's UI and
server modules. The client holds your app's sign-in settings; each
visitor signs in with their own account.

## Usage

``` r
oauth_db_microsoft_client(
  services = "sql",
  tenant_id,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  provider = shinyOAuth::oauth_provider_microsoft(tenant = tenant_id, id_token_validation
    = TRUE, userinfo_required = FALSE),
  token_targets = .odb_microsoft_targets(services),
  token_target_default = if (length(token_targets)) {
names(token_targets)[[1L]]
 }
    else {
     character()
 },
  scopes = .odb_microsoft_client_scopes(services, token_targets)
)
```

## Arguments

- services:

  One or more of `"sql"`, `"postgres"`, `"mysql"`, `"fabric"`, `"kql"`,
  `"dax"`, `"graphql"`, `"onelake"`, or `"databricks_entra"`. The first
  service selects the default token target.

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

- provider:

  Custom shinyOAuth provider, replacing the default.

- token_targets:

  Named token targets, replacing the service defaults. Use
  [`list()`](https://rdrr.io/r/base/list.html) for a client without
  named targets. In that case, default scopes come from `services`,
  which must select one resource. Supply `scopes` explicitly to replace
  those consent defaults.

- token_target_default:

  Default target name, or
  [`character()`](https://rdrr.io/r/base/character.html) for none.

- scopes:

  OAuth scopes to request, replacing the defaults.

## Value

A shinyOAuth `OAuthClient`. Create it outside `server()`.

## Details

Register the Shiny app in Microsoft Entra with the exact `redirect_uri`
and delegated permissions for the services it uses. Delegated access
lets the app act on behalf of the person who signs in. Users also need
permission to access the database or Fabric items.

The preset creates named token targets for the selected services. Custom
`scopes`, `provider` and `token_targets` replace their defaults. An
existing shinyOAuth client can also supply suitable tokens.

When PostgreSQL or MySQL is combined with other services, its preset
requests `user_impersonation` instead of `.default`. For a custom
resource such as Oracle Database, supply `token_targets`; the Oracle
vignette has an example.

## See also

[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md)
explains sign-in settings and links to each source's setup guide.

## Examples

``` r
if (FALSE) { # \dontrun{
client <- oauth_db_microsoft_client(
  services = c("fabric", "sql"),
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
)
} # }
```
