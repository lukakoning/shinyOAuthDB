.odb_sql_capabilities <- function(
  package,
  transactions = TRUE,
  strategy = "worker_connection"
) {
  list(
    native_dbi = TRUE,
    sql = TRUE,
    transactions = transactions,
    async_strategy = strategy,
    connector_package = package,
    connection_reuse = "session",
    token_refresh = "new_connection",
    query_deadline = FALSE,
    remote_cancellation = FALSE,
    delegated_user = TRUE,
    live_verified = FALSE
  )
}

.odb_sql_protected <- c(
  "conn",
  "connection",
  "drv",
  "driver",
  "server",
  "host",
  "port",
  "database",
  "dbname",
  "user",
  "uid",
  "pwd",
  "password",
  "token",
  "token_provider",
  "attributes",
  "dsn",
  ".connection_string",
  "connection_string",
  "authentication",
  "authenticator",
  "auth_args",
  "trusted_connection",
  "integrated_security",
  "encrypt",
  "sslmode",
  "sslrootcert",
  "trustservercertificate",
  "token_file_path",
  "role",
  "warehouse",
  "schema",
  "catalog"
)

#' Describe an Azure SQL database
#'
#' Sources hold application configuration, never OAuth credentials. The adapter
#' returns a native odbc DBI connection using the delegated user's access token.
#' Database users/groups, permissions, an Entra registration and network access
#' must already be configured. Driver-manager pooling is a deployment concern.
#'
#' @param server Database hostname without scheme or port.
#' @param database Database name.
#' @param target Declared shinyOAuth token-target name.
#' @param driver Installed Microsoft SQL Server ODBC driver name.
#' @param port TCP port.
#' @param scopes Fully qualified delegated scopes. Preserve the SQL resource's
#'   trailing slash: the permission URL contains two slashes before the scope.
#' @param options Named native-driver options. Authentication, endpoint and TLS
#'   settings cannot be overridden.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_azure_sql <- function(
  server,
  database,
  target = "sql",
  driver = "ODBC Driver 18 for SQL Server",
  port = 1433L,
  scopes = "https://database.windows.net//user_impersonation",
  options = list()
) {
  .odb_source_string(database, "database")
  .odb_source_string(driver, "driver")

  .odb_source_odbc_value(database)
  .odb_source_odbc_value(driver)
  config <- list(
    server = .odb_source_host(server),
    database = database,
    driver = driver,
    port = .odb_source_port(port),
    options = .odb_source_odbc_options(
      options,
      c(
        "timezone",
        "timezone_out",
        "encoding",
        "name_encoding",
        "bigint",
        "timeout",
        "interruptible",
        "ApplicationIntent"
      )
    )
  )

  .odb_new_source(
    "azure_sql",
    config,
    "microsoft",
    target,
    "https://database.windows.net/",
    scopes,
    capabilities = .odb_sql_capabilities("odbc"),
    protected_args = .odb_sql_protected
  )
}

#' Describe an explicitly Entra-enabled SQL Server
#'
#' Ordinary SQL authentication and the Shiny host's Windows identity do not
#' authenticate the visitor. This adapter requires configured native Entra access
#' token support, for example on an appropriately configured SQL Server 2022+.
#' @inheritParams oauth_db_azure_sql
#' @param entra_enabled Explicit declaration that the server has Entra token
#'   authentication configured. Must be `TRUE`.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_sql_server <- function(
  server,
  database,
  entra_enabled = FALSE,
  target = "sql",
  driver = "ODBC Driver 18 for SQL Server",
  port = 1433L,
  scopes = "https://database.windows.net//user_impersonation",
  options = list()
) {
  if (!identical(entra_enabled, TRUE)) {
    .odb_source_error(
      "SQL Server needs configured native Entra authentication. Set entra_enabled = TRUE only after that setup; ordinary SQL/Windows authentication cannot reuse the app visitor's OAuth identity.",
      "unsupported_authentication"
    )
  }

  source <- oauth_db_azure_sql(
    server,
    database,
    target,
    driver,
    port,
    scopes,
    options
  )

  .odb_new_source(
    "sql_server",
    c(source$config, list(entra_enabled = TRUE)),
    "microsoft",
    target,
    source$auth$resource,
    scopes,
    capabilities = source$capabilities,
    protected_args = source$protected_args
  )
}

#' Describe Entra access to Azure PostgreSQL Flexible Server
#'
#' Uses RPostgres and the user's token as a libpq password. This is not the
#' PostgreSQL 18 native OAUTHBEARER protocol. `user` is a provisioned individual
#' or group database role, configured by trusted application code.
#' @param host PostgreSQL server hostname.
#' @param database Database name.
#' @param user Provisioned Entra database role name.
#' @param target Declared shinyOAuth token-target name.
#' @param port TCP port.
#' @param sslrootcert Trusted CA bundle path, or `NULL` to use libpq's configured
#'   root certificate. Certificate verification is always enabled.
#' @param resource Exact Entra resource, configurable for sovereign deployments.
#' @param scopes Declared consent profile. The documented default uses `.default`
#'   and cannot automatically be mixed with explicit consent in one client.
#' @param required_scopes Explicit token permissions to check; defaults empty
#'   for a `.default` consent profile.
#' @param options Named non-credential libpq/RPostgres options.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_azure_postgres <- function(
  host,
  database,
  user,
  target = "postgres",
  port = 5432L,
  sslrootcert = NULL,
  resource = "https://ossrdbms-aad.database.windows.net",
  scopes = paste0(resource, "/.default"),
  required_scopes = if (any(endsWith(scopes, "/.default"))) {
    character()
  } else {
    scopes
  },
  options = list()
) {
  for (name in c("database", "user")) {
    .odb_source_string(get(name), name)
  }

  .odb_source_string(sslrootcert, "sslrootcert", nullable = TRUE)

  config <- list(
    host = .odb_source_host(host, "host"),
    database = database,
    user = user,
    port = .odb_source_port(port),
    sslrootcert = sslrootcert,
    options = .odb_source_options(
      options,
      c(
        "connect_timeout",
        "application_name",
        "bigint",
        "check_interrupts",
        "timezone",
        "timezone_out"
      )
    )
  )
  capabilities <- .odb_sql_capabilities("RPostgres")
  capabilities$transaction_caveat <- "A broken connection can be reset by libpq; no transaction replay is provided"
  capabilities$native_reconnect <- "libpq may reset a broken connection with the original token"

  .odb_new_source(
    "azure_postgres",
    config,
    "microsoft",
    target,
    resource,
    scopes,
    required_scopes,
    capabilities,
    .odb_sql_protected
  )
}

#' Describe a Snowflake OAuth connection
#'
#' The provider, resource, scope and database role must match the account's
#' configured OAuth integration. The adapter always uses `authenticator=oauth`
#' with the delegated token and does not invoke driver-owned login flows.
#' @param server Snowflake account hostname.
#' @param database,schema,warehouse,role Explicit Snowflake connection context.
#' @param driver Installed Snowflake ODBC driver.
#' @param auth_mode External OAuth or native Snowflake OAuth.
#' @param provider_family Explicit provider family for external OAuth.
#' @param resource Exact configured external OAuth resource; native OAuth may
#'   leave it `NULL`.
#' @param scopes Scopes configured by this account's security integration.
#' @param required_scopes Explicit token permissions to check.
#' @param target Declared shinyOAuth token-target name.
#' @param options Named non-credential ODBC options.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_snowflake <- function(
  server,
  database,
  schema,
  warehouse,
  role,
  driver = "SnowflakeDSIIDriver",
  auth_mode = c("external_oauth", "snowflake_oauth"),
  provider_family = NULL,
  resource = NULL,
  scopes,
  required_scopes = scopes,
  target = if (auth_mode[[1L]] == "snowflake_oauth") NULL else "snowflake",
  options = list()
) {
  auth_mode <- match.arg(auth_mode)
  for (name in c("database", "schema", "warehouse", "role", "driver")) {
    .odb_source_string(get(name), name)

    .odb_source_odbc_value(get(name))
  }
  if (auth_mode == "snowflake_oauth") {
    if (!is.null(provider_family) && provider_family != "snowflake") {
      .odb_source_error(
        "Native Snowflake OAuth requires provider_family = 'snowflake'."
      )
    }

    provider_family <- "snowflake"
  } else {
    .odb_source_string(provider_family, "provider_family")
    .odb_source_string(resource, "resource")
  }

  config <- list(
    server = .odb_source_host(server),
    database = database,
    schema = schema,
    warehouse = warehouse,
    role = role,
    driver = driver,
    auth_mode = auth_mode,
    options = .odb_source_odbc_options(
      options,
      c("timezone", "timezone_out", "bigint", "timeout", "interruptible")
    )
  )

  .odb_new_source(
    "snowflake",
    config,
    provider_family,
    target,
    resource,
    scopes,
    required_scopes,
    .odb_sql_capabilities("odbc"),
    c(
      .odb_sql_protected,
      "auth_mode",
      "oauth_client_id",
      "oauth_client_secret",
      "oauth_scope"
    )
  )
}
