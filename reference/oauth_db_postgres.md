# Query PostgreSQL as the signed-in user

Read PostgreSQL data in a Shiny app using each visitor's account and
existing database permissions. This helper uses PostgreSQL's native
OAuth support and opens an RPostgres connection for DBI or dbplyr
queries.

## Usage

``` r
oauth_db_postgres(
  authorization,
  host,
  dbname,
  user,
  issuer,
  scope,
  ...,
  port = 5432L,
  sslrootcert = NULL,
  connect_timeout = 5L,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- host:

  One TCP hostname or address.

- dbname:

  Database name.

- user:

  Requested database role, or a function deriving it from the selected
  sign-in's validated identity. PostgreSQL checks that the token may use
  that role according to the server's identity mapping.

- issuer:

  Exact HTTPS issuer identifier configured on PostgreSQL.

- scope:

  Space-separated scopes configured in the server's OAuth authentication
  rule. These scopes are also checked before connecting.

- ...:

  RPostgres result options (`bigint`, `check_interrupts`, `timezone`,
  `timezone_out`), `application_name`, or TCP keepalive options.
  Authentication and TLS options cannot be overridden.

- port:

  TCP port, default `5432`.

- sslrootcert:

  CA certificate bundle path, or `NULL` for libpq defaults.

- connect_timeout:

  Connection timeout in whole seconds, at least two.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  Additional OAuth permissions to check before use. Request them on the
  shinyOAuth client first; this check doesn't request consent or grant
  database privileges.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression, then pass the connection to DBI.
Before sign-in, the function waits quietly.

## Details

Native OAuth requires Linux, PostgreSQL 18, and RPostgres and
shinyOAuthDB built against the same shared libpq 18. Install libpq
without its optional device-flow module; shinyOAuth handles browser
sign-in and token renewal. Other platforms can run the Docker demo or
use
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md).

Configure the server's OAuth validator, trusted issuer and audience, and
the mapping from users to database roles. Connections require OAuth and
verified TLS. The PostgreSQL vignette has a working Keycloak
configuration.

Create the helper inside `server()` and call `con()` before each query.
A valid connection stays open through token renewal. Account or role
changes and sign-out close it. If it breaks, reopen through `con()`;
resetting or cloning a saved connection isn't supported.

## Try the Docker demo

With Docker running, call
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
to try PostgreSQL, Keycloak sign-in and a Shiny app with sample data on
Windows, macOS or Linux. Use `oauth_db_demo(action = "files")` to copy
the configuration.

The [PostgreSQL
guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html)
covers the demo and setup for your own server.

## See also

[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md)
for Azure's Entra authentication.

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside server(), with an OIDC client requesting openid, profile and database.read:
con <- oauth_db_postgres(
  auth$connection,
  host = "postgres.example.org", dbname = "reporting",
  user = function() {
    reference <- shiny::req(auth$connection())
    identity <- reference$identity(claims = "preferred_username")
    shiny::req(identity$id_token_claims$preferred_username)
  },
  issuer = "https://login.example.org/realms/reporting",
  scope = "database.read", sslrootcert = "path/to/ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
