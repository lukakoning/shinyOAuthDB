# Create a Databricks OAuth provider

Use this to choose provider settings when constructing
`shinyOAuth::oauth_client()` yourself. For a typical app, use
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md).

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

The function makes an HTTPS request to discover the workspace's sign-in
endpoints.

## See also

[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md).
[`vignette("databricks", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/databricks.md)
has sign-in setup and a complete app.

Other sign-in configuration:
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md),
[`oauth_db_snowflake_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_provider.md)
