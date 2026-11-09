# Query SAP HANA as the signed-in user

Read SAP HANA or HANA Cloud data using each visitor's database
privileges. HANA checks their signed access token and maps it to a
database user. The helper provides a DBI connection for SQL or dbplyr
queries.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

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

Install odbc and SAP HANA Client's ODBC driver. Configure HANA to trust
your provider's JWT access tokens, map their identities to database
users and grant access to the data. The scope and audience depend on
that configuration; a SAP BTP browser login alone doesn't establish SQL
access.

Create the helper inside `server()` and call `con()` before each query.
The connection requires encryption and a trusted server certificate. A
valid SQL session stays open through ordinary token renewal, with the
identity and privileges established when it connected.

Sign-out, account changes or session end close the connection. If it
breaks, the next `con()` reconnects with a current token. The helper
doesn't replay a failed query.

## See also

[`vignette("hana", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/hana.md)
for sign-in, database configuration and a complete Shiny app.

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
