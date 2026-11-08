# Create a Snowflake OAuth provider

Use this to choose provider settings when constructing
`shinyOAuth::oauth_client()` yourself. For a typical app, use
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md).

## Usage

``` r
oauth_db_snowflake_provider(server, ...)
```

## Arguments

- server:

  Snowflake account hostname.

- ...:

  Settings for
  [`shinyOAuth::oauth_provider()`](https://lukakoning.github.io/shinyOAuth/reference/oauth_provider.html),
  replacing defaults.

## Value

A shinyOAuth `OAuthProvider` for Snowflake's own OAuth integration.

## Details

External OAuth uses the external identity provider's configuration.

## See also

[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md).
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
has sign-in setup and a complete app.

Other sign-in configuration:
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks_provider()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_provider.md),
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md),
[`oauth_db_supabase_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_client.md)
