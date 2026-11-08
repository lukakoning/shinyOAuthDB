# Query Oracle Database as the signed-in user

Open an Oracle ODBC connection with the visitor's Microsoft Entra access
token. Use the connection with DBI or dbplyr against an Oracle database
configured for Entra authentication, on your infrastructure or in the
cloud.

## Usage

``` r
oauth_db_oracle(
  authorization,
  host,
  service_name,
  driver,
  ...,
  port = 1522L,
  wallet_location = NULL,
  server_cert_dn = NULL,
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

- host:

  One Oracle TCPS listener hostname or IP address.

- service_name:

  Oracle database service name, not a SID or TNS alias.

- driver:

  Registered Oracle ODBC driver name, or its library path when supported
  by the driver manager. Use Oracle Instant Client with OAuth support:
  19.16 or later in the 19c line, or a supported newer release. The 21c
  thick client does not support this integration.

- ...:

  Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
  `encoding`, `name_encoding`, or `interruptible`; Oracle ODBC options
  `FBS` (fetch buffer size) and `DBA` (`"R"` for read-only, `"W"` for
  read/write) are also accepted.

- port:

  TCPS listener port. Defaults to `1522`; use the port supplied by your
  administrator, which may differ for self-hosted databases.

- wallet_location:

  Optional Oracle wallet directory for TLS trust or mutual TLS. `NULL`
  uses the Oracle client's configured trust store.

- server_cert_dn:

  Optional expected server certificate distinguished name. `NULL` uses
  Oracle's hostname matching. Certificate matching is always enabled.

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

Install odbc and Oracle Instant Client's Basic and ODBC packages. The
database must support and enable Microsoft Entra integration and map the
visitor to a global database schema. Request delegated access to that
database's own Entra application resource. Azure SQL tokens and
arbitrary OIDC tokens are not interchangeable with Oracle access tokens.
See
[`vignette("oracle", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md)
for sign-in setup.

Create the helper inside `server()` and call `con()` before each
operation. Valid SQL sessions survive ordinary token renewal. Account
changes, sign-out, permission loss and session end close the connection.
A broken connection is reopened with the current token on the next
`con()` call.

The helper builds a separate TCPS descriptor for each connection. It
sets `TOKEN_AUTH=OAUTH`, supplies the token through a private temporary
file, and removes that file on success, error or interrupt. On Windows
the directory inherits R's temporary-directory access rules; run R with
a private user temporary directory. Shared `TNS_ADMIN`, `tnsnames.ora`,
and `sqlnet.ora` files are not modified.

Oracle ODBC failover is disabled because the temporary token file is
removed after connection opening. Before returning a connection, the
helper checks that Oracle reports `TOKEN_GLOBAL` authentication and
disconnects otherwise. DSNs, alternate credentials and authentication
overrides cannot be supplied through `...`. OCI IAM proof-of-possession
tokens and password authentication are outside this helper's scope.

## See also

[`vignette("oracle", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md).

Other database connections:
[`oauth_db_azure_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_postgres.md),
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_duckdb()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_duckdb.md),
[`oauth_db_fabric_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_sql.md),
[`oauth_db_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgres.md),
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md),
[`oauth_db_snowflake()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake.md),
[`oauth_db_sql_server()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_sql_server.md),
[`oauth_db_starrocks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_starrocks.md),
[`oauth_db_trino()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_trino.md)

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_oracle(
  auth$connection,
  host = "database.example.org",
  service_name = "reporting.example.org",
  driver = "Oracle in instantclient_19_30"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT USER AS database_user FROM DUAL")
})
} # }
```
