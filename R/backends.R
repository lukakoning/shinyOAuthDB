#' Use the user's authorization with Azure SQL
#'
#' These helpers adapt the user's authorization to a native client. Call the
#' accessor inside an ordinary Shiny reactive or render function to obtain the
#' native connection or credential provider. Connections open on first use.
#' Supply driver options directly in `...`; query arguments stay in your native
#' database call. Authentication and certificate verification cannot be
#' overridden through `...`.
#'
#' @inheritParams oauth_db_connect
#' @param server Database hostname.
#' @param database Database name.
#' @param driver Installed ODBC driver name.
#' @param port Database port.
#' @param ... Additional named options passed to the native connection function.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_azure_sql <- function(
  authorization, server, database, ...,
  target = "sql", scopes = "https://database.windows.net//user_impersonation",
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.3.4")
  .odb_backend_odbc_values(list(server, database, driver, port))
  options <- .odb_backend_options(list(...), c("server", "database", "driver", "port"), odbc = TRUE)
  .odb_bind(authorization, .odb_backend_sql, server = server, database = database,
    driver = driver, port = port, options = options, target = target,
    scopes = scopes, min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with an Entra-enabled SQL Server
#'
#' An alias of [oauth_db_azure_sql()] for SQL Server deployments configured
#' to accept Entra access tokens. The server must already support this login.
#' @inheritParams oauth_db_azure_sql
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_sql_server <- oauth_db_azure_sql

#' Use the user's authorization with Azure PostgreSQL
#'
#' Uses RPostgres with the user's Entra token as the password. The provisioned
#' database role and server permissions must already exist. The default
#' `.default` scope is a consent request, not a literal token permission.
#' @inheritParams oauth_db_azure_sql
#' @param host PostgreSQL hostname.
#' @param user Provisioned individual or group database role.
#' @param sslrootcert CA bundle path, or `NULL` for libpq's configured CA bundle.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_azure_postgres <- function(
  authorization, host, database, user, ..., port = 5432L, sslrootcert = NULL,
  target = "postgres", scopes = "https://ossrdbms-aad.database.windows.net/.default",
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("RPostgres")
  .odb_string(host, "host")
  .odb_string(database, "database")
  .odb_string(user, "user")
  options <- .odb_backend_options(list(...), c("host", "dbname", "port", "sslrootcert", "service", "passfile"))
  .odb_bind(authorization, .odb_backend_postgres, host = host, database = database,
    user = user, port = port, sslrootcert = sslrootcert, options = options,
    target = target, scopes = scopes, min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with Fabric SQL
#'
#' Delegates connection details and the ODBC or ADBC transport to
#' `fabricQueryR::fabric_sql_connect()`. Pass its native options such as
#' `backend`, `odbc_driver`, `read_only`, and `timeout` in `...`.
#' @inheritParams oauth_db_azure_sql
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_fabric_sql <- function(
  authorization, server, database = NULL, ..., target = "sql",
  scopes = "https://database.windows.net//user_impersonation",
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("fabricQueryR")
  options <- .odb_backend_options(list(...), c("server", "database", "tenant_id", "client_id"))
  .odb_bind(authorization, .odb_backend_fabric_sql, server = server,
    database = database, provider_scopes = scopes,
    options = options, target = target, scopes = scopes,
    min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with native Fabric functions
#'
#' Returns an ordinary callback accepted by fabricQueryR's `token` argument.
#' This package owns the OAuth adaptation; no Shiny helpers or provider
#' extensions in fabricQueryR are required. Endpoints, item IDs and query options
#' belong in the native call. Keep endpoints in trusted application configuration.
#' The callback supplies only the configured service's audience and scopes.
#' @inheritParams oauth_db_connect
#' @inheritParams oauth_db_fabric_sql
#' @param service One Fabric service: `"fabric"`, `"sql"`, `"dax"`, `"kql"`,
#'   `"onelake"` or `"graphql"`.
#' @param target Declared shinyOAuth target, defaulting to the service's target.
#'   Set `NULL` to use the authorization's own default, including clients without
#'   named token targets.
#' @param scopes Delegated scopes; `NULL` uses the service's query/read defaults.
#' @returns A session-local reactive accessor for a native token provider.
#' @export
oauth_db_fabric <- function(
  authorization, service = c("fabric", "sql", "dax", "kql", "onelake", "graphql"),
  target = .odb_backend_profile(service)$target, scopes = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  service <- match.arg(service)
  profile <- .odb_backend_profile(service)
  if (is.null(scopes)) scopes <- profile$scopes
  .odb_bind(authorization, .odb_backend_fabric, service = service,
    provider_scopes = scopes, target = target,
    scopes = scopes, min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with Databricks
#'
#' With `warehouse_id`, the native value is a brickster DBI connection. Without
#' it, the accessor returns a current bearer string for brickster's `token`
#' argument. Works with upstream brickster, without a fork or Shiny extensions.
#' Call the accessor for each operation. Its native DBI connection holds a fixed
#' token, so the accessor replaces it when shinyOAuth refreshes the credential.
#' A previously returned connection or string is a snapshot; do not retain it
#' across operations or authorizations. Endpoints belong in app configuration.
#' @inheritParams oauth_db_connect
#' @param host Databricks workspace hostname or HTTPS origin. Required for a
#'   DBI connection with `warehouse_id`; omit for a bearer-string accessor.
#' @param warehouse_id SQL warehouse ID, or `NULL` for a bearer-string accessor.
#' @param ... Native `DBI::dbConnect()` options, such as `catalog` and `schema`.
#' @param auth_mode `"databricks_oauth"` or `"entra"` for Azure Databricks.
#' @param target Declared token target. Defaults to `"databricks"` for Entra;
#'   native Databricks OAuth uses the main authorization.
#' @param scopes Delegated scopes, or `NULL` for the chosen authentication mode.
#' @returns A session-local reactive accessor for a native connection or bearer string.
#' @export
oauth_db_databricks <- function(
  authorization, host = NULL, warehouse_id = NULL, ...,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  scopes = NULL, min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  if (is.null(scopes)) {
    scopes <- .odb_backend_profile(if (auth_mode == "entra") "databricks_entra" else "databricks")$scopes
  }
  if (!is.null(host)) host <- .odb_databricks_host(host)
  options <- .odb_backend_options(list(...), c("host", "warehouse_id", "http_path"))
  if (is.null(warehouse_id) && length(options)) {
    .odb_abort("Connection options in ... require a warehouse_id; pass REST options to the native call.")
  }
  if (is.null(warehouse_id)) {
    return(oauth_db_token(authorization, target = target, scopes = scopes,
      min_valid_for = min_valid_for, session = session))
  }
  if (is.null(host)) .odb_abort("Supply host when warehouse_id requests a Databricks DBI connection.")
  .odb_require("brickster")
  .odb_bind(authorization, .odb_backend_databricks, host = host,
    warehouse_id = warehouse_id, options = options, target = target,
    scopes = scopes, refresh_token = TRUE, min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with Snowflake
#'
#' Configure the OAuth client in shinyOAuth to match the account's native or
#' external OAuth integration. Native Snowflake OAuth derives its scope from
#' `role`; supply explicit `scopes` for an external or customized integration.
#' The ODBC driver receives `authenticator = "oauth"` and the user's access token.
#' @inheritParams oauth_db_azure_sql
#' @param schema,warehouse,role Explicit Snowflake connection context.
#' @param scopes Scopes configured by the account's OAuth integration. Defaults
#'   to `paste0("session:role:", role)` for native Snowflake OAuth.
#' @param target Optional named shinyOAuth token target for external OAuth.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_snowflake <- function(
  authorization, server, database, schema, warehouse, role, ...,
  scopes = paste0("session:role:", role),
  target = NULL, driver = "SnowflakeDSIIDriver", min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc")
  .odb_string(role, "role")
  .odb_backend_odbc_values(list(server, database, schema, warehouse, role, driver))
  options <- .odb_backend_options(list(...), c("server", "database", "schema", "warehouse", "role", "driver"), odbc = TRUE)
  .odb_bind(authorization, .odb_backend_snowflake, server = server,
    database = database, schema = schema, warehouse = warehouse, role = role,
    driver = driver, options = options, target = target, scopes = scopes,
    min_valid_for = min_valid_for, session = session)
}

# Native factories receive a pinned credential callback and connection options.
.odb_backend_sql <- function(token, server, database, driver, port, options) {
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver,
    server = paste0(server, ",", port), database = database, Encrypt = "yes",
    TrustServerCertificate = "no", attributes = list(azure_token = token())), options))
}

.odb_backend_postgres <- function(token, host, database, user, port, sslrootcert, options) {
  args <- list(drv = RPostgres::Postgres(), host = host, dbname = database,
    user = user, port = port, password = token(), sslmode = "verify-full")
  if (!is.null(sslrootcert)) args$sslrootcert <- sslrootcert
  do.call(DBI::dbConnect, c(args, options))
}

.odb_backend_fabric <- function(token, service, provider_scopes) {
  force(token)
  allowed <- c(paste0(.odb_backend_profile(service)$resource, "/.default"), provider_scopes)
  force(allowed)
  function(audience, force_refresh = FALSE) {
    if (!is.character(audience) || !length(audience) || anyNA(audience) ||
        !all(audience %in% allowed)) {
      .odb_abort("The Fabric callback cannot supply tokens for this audience or scope.", "invalid_audience")
    }
    token(force_refresh = force_refresh)
  }
}

.odb_backend_fabric_sql <- function(token, server, database, provider_scopes, options) {
  provider <- .odb_backend_fabric(token, "sql", provider_scopes)
  do.call(fabricQueryR::fabric_sql_connect, c(list(server = server, database = database,
    token = provider, encrypt = "yes", trust_server_certificate = "no"), options))
}

.odb_backend_databricks <- function(token, host, warehouse_id, options) {
  do.call(DBI::dbConnect, c(list(drv = brickster::DatabricksSQL(), host = host,
    warehouse_id = warehouse_id, token = token()), options))
}

.odb_backend_snowflake <- function(token, server, database, schema, warehouse, role, driver, options) {
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver, server = server,
    database = database, schema = schema, warehouse = warehouse, role = role,
    authenticator = "oauth", token = token()), options))
}

.odb_backend_options <- function(options, blocked = character(), odbc = FALSE) {
  key <- function(x) tolower(gsub("[^A-Za-z0-9]", "", x))
  nms <- names(options)
  if (length(options) && (is.null(nms) || any(!nzchar(nms)) || anyDuplicated(key(nms)))) {
    .odb_abort("Native options in ... must have unique names.")
  }
  protected <- c("token", "access_token", "sql_token", "token_provider", "attributes",
    "user", "uid", "pwd", "password", "dsn", "drv", ".connection_string",
    "connection_string", "authentication", "authenticator", "auth_args",
    "trusted_connection", "integrated_security", "encrypt", "sslmode",
    "trust_server_certificate", "token_file_path", "client_secret", "oauth_client_id",
    "oauth_client_secret", "oauth_scope", "insecure_mode", "disable_saml_url_check")
  if (any(key(nms) %in% key(c(protected, blocked)))) {
    .odb_abort("Authentication, connection identity and TLS settings cannot be overridden through ... .")
  }
  if (odbc) .odb_backend_odbc_values(options)
  options
}

.odb_backend_odbc_values <- function(values) {
  for (value in values) {
    if (is.character(value) && any(grepl("[;{}[:cntrl:]]", value))) {
      .odb_abort("ODBC values cannot contain connection-string delimiters or control characters.")
    }
  }
  invisible(values)
}

# OAuth recipes only: native clients own service operations and their arguments.
.odb_backend_profile <- function(service) {
  recipe <- switch(service,
    sql = list("sql", "https://database.windows.net/", "user_impersonation"),
    postgres = list("postgres", "https://ossrdbms-aad.database.windows.net", ".default"),
    fabric = list("fabric", "https://api.fabric.microsoft.com", c("Workspace.Read.All", "Item.Read.All")),
    dax = list("power_bi", "https://analysis.windows.net/powerbi/api", "Dataset.Read.All"),
    kql = list("kusto", "https://api.kusto.windows.net", "user_impersonation"),
    onelake = list("storage", "https://storage.azure.com", "user_impersonation"),
    graphql = list("power_bi", "https://analysis.windows.net/powerbi/api", "GraphQLApi.Execute.All"),
    databricks = list(NULL, NULL, "all-apis"),
    databricks_entra = list("databricks", "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d", "user_impersonation"),
    .odb_abort(paste0("Unknown OAuth service: ", service)))
  list(target = recipe[[1L]], resource = recipe[[2L]], scopes = if (is.null(recipe[[2L]])) {
    recipe[[3L]]
  } else paste0(recipe[[2L]], "/", recipe[[3L]]))
}
