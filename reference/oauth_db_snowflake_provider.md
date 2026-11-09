# Create a Snowflake OAuth provider

Describe Snowflake's sign-in service when building a custom client with
`shinyOAuth::oauth_client()`. For an app using Snowflake's own OAuth
integration,
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md)
supplies the usual settings.

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

This provider uses Snowflake's own OAuth endpoints. An account using
External OAuth needs the external sign-in provider's configuration.

## See also

[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md).
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
has sign-in setup and a complete app.
