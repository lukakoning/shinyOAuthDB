# Query Azure PostgreSQL as the signed-in user

Read Azure Database for PostgreSQL data using each visitor's Microsoft
account. The database maps that account to a user or group role with
permission to query the data. The RPostgres connection works with DBI or
dbplyr.

## Usage

``` r
oauth_db_azure_postgres(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 5432L,
  sslrootcert = NULL,
  target = "postgres",
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

  PostgreSQL hostname.

- dbname:

  Database name.

- user:

  Database role created for the user or their group.

- ...:

  RPostgres result options (`bigint`, `check_interrupts`, `timezone`,
  `timezone_out`), `connect_timeout`, `application_name`, or TCP
  keepalive options. Authentication and TLS options cannot be
  overridden.

- port:

  Database port.

- sslrootcert:

  CA certificate bundle path, or `NULL` to use libpq's configured
  bundle.

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

Install RPostgres linked to libpq 16 or later. Configure Azure
PostgreSQL for Entra authentication and create database roles for the
users or their groups. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "postgres"`.

Create the helper inside `server()` and call `con()` before querying.
The connection uses verified TLS and sends the visitor's access token as
the password. The server must use that authentication method; Kerberos,
certificate-only and trust authentication aren't supported by this
helper.

After the access token changes, the next `con()` call replaces the
connection so a lost session can reconnect with current credentials.
Complete a transaction using the connection that started it; get a
connection for the next operation through `con()`.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
[`vignette("azure-postgres", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_azure_postgres(
  auth$connection,
  host = "example.postgres.database.azure.com",
  dbname = "reporting",
  user = "reporting-readers",
  sslrootcert = "path/to/root-ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
