# Query Cloud SQL for PostgreSQL as the signed-in user

Open a Cloud SQL for PostgreSQL connection with the visitor's Google
access token as the IAM database password. Queries work with DBI and
dbplyr.

## Usage

``` r
oauth_db_cloud_sql_postgres(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 5432L,
  hostaddr = NULL,
  sslrootcert = NULL,
  sslcert = NULL,
  sslkey = NULL,
  target = NULL,
  required_scopes = "https://www.googleapis.com/auth/sqlservice.login",
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

  One database hostname matching its TLS server certificate.

- dbname:

  Database name.

- user:

  IAM database username, or a function returning it for the selected
  account. For a Google user, this is their full email address. The
  server checks that the token belongs to that IAM identity.

- ...:

  RPostgres options: `bigint`, `check_interrupts`, `timezone`,
  `timezone_out`, `connect_timeout`, `application_name`, or TCP
  keepalives (`keepalives`, `keepalives_idle`, `keepalives_interval`,
  `keepalives_count`, `tcp_user_timeout`). Authentication and TLS
  settings cannot be overridden.

- port:

  Database TCP port.

- hostaddr:

  Optional server IP address. `host` still supplies the name checked
  against the certificate.

- sslrootcert:

  Trusted server CA certificate file, or `NULL` for libpq's configured
  trust store.

- sslcert, sslkey:

  Optional client certificate and private key files. Supply both if the
  instance requires a client certificate.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  OAuth scopes to check before opening a connection. Defaults to
  Google's Cloud SQL login scope. Set explicitly when a custom client
  uses an alternative accepted scope; this check doesn't grant IAM or
  database privileges.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A reactive function returning a native RPostgres DBI connection.

## Details

Enable Cloud SQL IAM database authentication, add the user's IAM account
or group, grant Cloud SQL Instance User, and grant SQL privileges
separately. Use
[`oauth_db_cloud_sql_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_sql_client.md)
for Google sign-in. The app host needs a direct network route to the
instance and a hostname matching its certificate. Shared or
customer-managed server CAs can provide such DNS names; see the source
guide for per-instance CA restrictions.

Install RPostgres linked to libpq 16 or later. Connections require
password authentication and verified TLS (`sslmode = "verify-full"`),
with GSS encryption disabled. Unset `PGSERVICE` and `PGSERVICEFILE`;
connection service files cannot supply alternative settings.

Create the helper inside `server()` and get `connection <- con()` before
each operation. When the token changes, the next `con()` call closes the
old connection and opens one with current credentials. Ordinary renewal
doesn't replay completed reactive queries. Finish a transaction on the
connection that started it. Account changes, permission loss, sign-out
and session end close the managed connection.

The helper uses manual IAM database authentication with visitor tokens.
It doesn't use a proxy's automatic IAM login or the hosting account's
credentials. Cloud SQL MySQL and SQL Server aren't supported by this
helper.

## See also

[`oauth_db_cloud_sql_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_sql_client.md).
[`vignette("cloud-sql", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-sql.md).

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_cloud_sql_postgres(
  auth$connection, host = "db.example.org", dbname = "reporting",
  user = "analyst@example.org", sslrootcert = "server-ca.pem"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT current_user")
})
} # }
```
