# Query Azure MySQL as the signed-in user

Read Azure Database for MySQL Flexible Server data with each visitor's
Microsoft account and database permissions. The helper opens a MariaDB
Connector/ODBC connection for DBI or dbplyr queries.

## Usage

``` r
oauth_db_azure_mysql(
  authorization,
  server,
  database,
  user,
  driver,
  ...,
  port = 3306L,
  ssl_ca = NULL,
  target = "mysql",
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

  One MySQL server hostname, usually ending in
  `.mysql.database.azure.com`.

- database:

  Default database name.

- user:

  Entra user or group name created in MySQL, or a reactive function
  returning that name. The server checks the identity mapping.

- driver:

  Registered MariaDB Connector/ODBC driver name. Some driver managers
  also accept a library path. Use MariaDB Connector/ODBC 3.1 or later.
  MySQL Connector/ODBC uses different options and is not supported by
  this helper.

- ...:

  Result and timeout options: `timeout`, `timezone`, `timezone_out`,
  `bigint`, `encoding`, `name_encoding`, `interruptible`, or
  `FORWARDONLY`.

- port:

  TCP port, default `3306`.

- ssl_ca:

  PEM CA certificate bundle path, or `NULL` to use the driver's trust
  configuration. Supply the bundle recommended for your Azure server.

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

Install odbc and MariaDB Connector/ODBC. Configure Azure MySQL for Entra
authentication and create users or groups with the required database
privileges. Use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with `services = "mysql"`.

The helper sends the visitor's access token as the password through
`mysql_clear_password`, with TLS certificate and hostname verification.
MariaDB's client library supplies the cleartext plugin without a global
environment setting. DSNs, option files, alternate credentials and
automatic reconnection are disabled.

Create the helper inside `server()` and call `con()` before each query.
The next access replaces the connection when its token or username
changes. Ordinary token renewal does not rerun completed reactive
queries. Sign-out, account changes and session end close the connection.
If a query reports a broken connection, disconnect that native handle
and call `con()` again. Failed queries are never replayed automatically.

## See also

[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md).
[`vignette("azure-mysql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/azure-mysql.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_azure_mysql(
  auth$connection,
  server = "example.mysql.database.azure.com",
  database = "reporting",
  user = "reporting-readers",
  driver = "MariaDB ODBC 3.2 Driver",
  ssl_ca = "path/to/azure-ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT CURRENT_USER() AS database_user")
})
} # }
```
