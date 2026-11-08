# Set up Microsoft sign-in for database access

Create a Microsoft Entra sign-in client for database and platform
access. Choose the services or token targets the app uses, then pass the
client to shinyOAuth's UI and server modules.

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

  One or more of `"sql"`, `"postgres"`, `"fabric"`, `"kql"`, `"dax"`,
  `"graphql"`, `"onelake"`, or `"databricks_entra"`. The first service
  selects the default token target.

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

The Entra registration needs delegated permissions for the selected
services. Users also need access to the database or Fabric items. When
PostgreSQL is combined with other services, its preset requests the
delegated `user_impersonation` scope instead of `.default`.

Custom `scopes`, `provider`, and `token_targets` replace their defaults.
An existing shinyOAuth client can be used in place of this preset. For a
deployment-specific resource such as Oracle Database, supply custom
`token_targets`; see
[`vignette("oracle", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md).

## See also

[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md)
links to each source's setup. For custom permissions and targets, see
[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md).

Other sign-in configuration:
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md),
[`oauth_db_salesforce_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_client.md),
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md),
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)

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
