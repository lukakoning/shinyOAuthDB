# Create a Databricks OAuth provider

Describe a Databricks workspace's sign-in service when building a custom
client with `shinyOAuth::oauth_client()`. The provider supplies the
sign-in and token endpoints. For the usual app setup, use
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md)
instead.

## Usage

``` r
oauth_db_databricks_provider(
  host,
  token_auth_style = c("header", "public"),
  ...
)
```

## Arguments

- host:

  Databricks workspace hostname or HTTPS origin.

- token_auth_style:

  `"header"` for a client with a secret, or `"public"` for an app
  registered without one.

- ...:

  Arguments for
  [`shinyOAuth::oauth_provider_oidc_discover()`](https://lukakoning.github.io/shinyOAuth/reference/oauth_provider_oidc_discover.html),
  replacing defaults.

## Value

A shinyOAuth `OAuthProvider`.

## Details

The function discovers the workspace's sign-in endpoints over HTTPS.
Choose `token_auth_style` to match the app registration: `"header"` for
a client with a secret, or `"public"` for one registered without a
secret.

## See also

[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.
