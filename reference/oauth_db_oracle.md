# Query Oracle Database as the signed-in user

Open an Oracle ODBC connection with the visitor's OAuth access token.
The database validates the provider's JWT and applies its configured
global-user or Oracle Deep Data Security authorization model.

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
  authorization_model = c("global", "end_user"),
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
  by the driver manager. Install a client that supports the database's
  OAuth integration; newer integrations need a current client.

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

- authorization_model:

  `"global"` requires Oracle to report `TOKEN_GLOBAL` authentication,
  preserving the global-schema model used by existing Entra
  configurations. `"end_user"` requires Oracle Deep Data Security to
  expose system-managed token claims matching the submitted JWT's
  issuer, subject and audience. It never falls back to global-schema
  privileges. Use this for configured OCI IAM OAuth and Keycloak
  direct-logon deployments.

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
database must trust the token's provider and audience and map the
visitor to a global schema or Deep Data Security data roles. Supported
routes include Microsoft Entra, OCI IAM Identity Domains OAuth, and the
configurable OAuth provider documented for Keycloak in Oracle 26ai.
Server and client version requirements differ between these
integrations; a JWT from an unconfigured provider does not establish
database access. See
[`vignette("oracle", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/oracle.md)
for sign-in setup.

Create the helper inside `server()` and call `con()` before each
operation. Global-schema sessions survive ordinary token renewal.
End-user sessions are reopened on access when the token changes, so new
identity and role claims reach the database without replaying completed
queries. Account changes, sign-out, permission loss and session end
close the connection. A broken connection is reopened with the current
token on access.

The helper builds a separate TCPS descriptor for each connection. It
sets `TOKEN_AUTH=OAUTH`, supplies the token through a private temporary
file, and removes that file on success, error or interrupt. On Windows
the directory inherits R's temporary-directory access rules; run R with
a private user temporary directory. Shared `TNS_ADMIN`, `tnsnames.ora`,
and `sqlnet.ora` files are not modified.

Oracle ODBC failover is disabled because the temporary token file is
removed after connection opening. Before returning a connection, the
helper verifies the selected authorization model and disconnects on
failure. In `"end_user"` mode, jsonlite is also required. Local JWT
decoding identifies the expected claims; Oracle verifies the signature
and establishes the system-managed context. DSNs, alternate credentials
and authentication overrides cannot be supplied through `...`.

Scope names are checked literally, as with generic OAuth helpers. Keep
Entra's `/.default` consent marker in the client configuration, not in
this helper's `required_scopes`. OCI IAM proof-of-possession tokens,
password authentication and application-mediated two-token contexts are
separate mechanisms. For ORDS REST resources use
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md).

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
