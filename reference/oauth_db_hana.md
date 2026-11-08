# Query SAP HANA as the signed-in user

Open a DBI connection to SAP HANA or SAP HANA Cloud using the visitor's
JWT access token. HANA maps the token's external identity to a database
user and applies that user's privileges.

## Usage

``` r
oauth_db_hana(
  authorization,
  server,
  database = NULL,
  ...,
  port = 443L,
  schema = NULL,
  driver = "HDBODBC",
  ssl_trust_store = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- server:

  One HANA SQL endpoint hostname or IPv4 address, without a protocol or
  port.

- database:

  Optional tenant database name. `NULL` uses the database selected by
  the SQL endpoint. HANA Cloud normally needs only its endpoint.

- ...:

  Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
  `encoding`, `name_encoding`, and `interruptible`. Native
  authentication, routing, reconnect and TLS settings cannot be
  overridden.

- port:

  SQL endpoint port, default `443` for HANA Cloud. For self-hosted HANA,
  use the SQL port supplied by your administrator.

- schema:

  Optional initial SQL schema. `NULL` uses the user's default.

- driver:

  Installed SAP HANA ODBC driver name, default `"HDBODBC"`, or a library
  path supported by the driver manager. Install a current SAP HANA
  Client with JWT authentication support.

- ssl_trust_store:

  Optional trust-store path for the SAP HANA Client's TLS provider.
  `NULL` uses the client's configured trust store.

- target:

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

A reactive function returning an odbc DBI connection.

## Details

Install odbc and SAP HANA Client's ODBC driver. Configure a JWT
provider, signing-certificate trust, external-identity mappings and user
privileges in the target database. The OAuth provider must issue a JWT
access token accepted by this configuration. Browser SSO for SAP BTP
alone does not establish SQL access. There is no universal SAP scope or
token audience.

The helper supplies the token as `PWD` with an empty `UID` and restricts
`authenticationMethods` to `jwt`. TLS encryption, certificate validation
and matching of the endpoint hostname are required. DSNs, saved user
credentials, session cookies and alternate authentication methods cannot
be selected through this helper.

Create the helper inside `server()` and call `connection <- con()`
before each query. Valid SQL sessions survive ordinary token renewal.
Account changes, permission loss, sign-out and Shiny session end close
them. Native automatic reconnect is disabled; reopen a broken connection
through `con()` to supply a current token. Failed queries are not
replayed.

## See also

[`vignette("hana", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/hana.md)
for sign-in, database configuration and a complete Shiny app.

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_hana(
  auth$connection,
  server = "example.hana.prod-eu10.hanacloud.ondemand.com",
  schema = "REPORTING"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT CURRENT_USER AS DATABASE_USER FROM DUMMY")
})
} # }
```
