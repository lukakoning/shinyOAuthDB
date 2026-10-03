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
#' Requires native Entra access-token authentication configured on the server.
#' @inheritParams oauth_db_azure_sql
#' @param entra_enabled Set `TRUE` to confirm the server supports Entra tokens.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_sql_server <- function(
  authorization, server, database, ..., entra_enabled = FALSE,
  target = "sql", scopes = "https://database.windows.net//user_impersonation",
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  if (!identical(entra_enabled, TRUE)) {
    .odb_abort("SQL Server must have Entra token authentication configured; set entra_enabled = TRUE.", "unsupported_authentication")
  }
  oauth_db_azure_sql(authorization, server, database, ..., target = target,
    scopes = scopes, driver = driver, port = port,
    min_valid_for = min_valid_for, session = session)
}

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
#' @param endpoint_hosts Additional exact trusted hostnames for custom endpoints.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_fabric_sql <- function(
  authorization, server, database, ..., target = "sql",
  scopes = "https://database.windows.net//user_impersonation",
  endpoint_hosts = character(), min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_backend_require_hook("fabricQueryR", "fabric_token_provider")
  options <- .odb_backend_options(list(...), c("server", "database", "tenant_id", "client_id"))
  .odb_bind(authorization, .odb_backend_fabric_sql, server = server,
    database = database, provider_scopes = scopes, endpoint_hosts = endpoint_hosts,
    options = options, target = target, scopes = scopes,
    min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with native Fabric functions
#'
#' The native value is a `fabricQueryR` token provider. Pass it as `token` to
#' any compatible native function. Endpoints, item IDs and query options belong
#' in that call. The provider retains fabricQueryR's audience and endpoint checks.
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
  endpoint_hosts = character(), min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  service <- match.arg(service)
  profile <- .odb_backend_profile(service)
  if (is.null(scopes)) scopes <- profile$scopes
  .odb_backend_require_hook("fabricQueryR", "fabric_token_provider")
  .odb_bind(authorization, .odb_backend_fabric, service = service,
    provider_scopes = scopes, endpoint_hosts = endpoint_hosts, target = target,
    scopes = scopes, min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with Databricks
#'
#' With `warehouse_id`, the native value is a brickster DBI connection. Without
#' it, the native value is a workspace-bound `brickster::db_token_provider()`;
#' pass it as `token` to native REST functions. The provider obtains credentials
#' for each request and never falls back to the host's credentials.
#' @inheritParams oauth_db_connect
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param warehouse_id SQL warehouse ID, or `NULL` for a native REST provider.
#' @param ... Native `DBI::dbConnect()` options, such as `catalog` and `schema`.
#' @param auth_mode `"databricks_oauth"` or `"entra"` for Azure Databricks.
#' @param target Declared token target. Defaults to `"databricks"` for Entra;
#'   native Databricks OAuth uses the main authorization.
#' @param scopes Delegated scopes, or `NULL` for the chosen authentication mode.
#' @returns A session-local reactive accessor for a native connection or provider.
#' @export
oauth_db_databricks <- function(
  authorization, host, warehouse_id = NULL, ...,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  scopes = NULL, min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  if (is.null(scopes)) {
    scopes <- .odb_backend_profile(if (auth_mode == "entra") "databricks_entra" else "databricks")$scopes
  }
  .odb_backend_require_hook("brickster", "db_token_provider")
  options <- .odb_backend_options(list(...), c("host", "warehouse_id", "http_path"))
  if (is.null(warehouse_id) && length(options)) {
    .odb_abort("Connection options in ... require a warehouse_id; pass REST options to the native call.")
  }
  .odb_bind(authorization, .odb_backend_databricks, host = host,
    warehouse_id = warehouse_id, options = options, target = target,
    scopes = scopes, min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with Snowflake
#'
#' Configure the OAuth client in shinyOAuth to match the account's native or
#' external OAuth integration. Supply that integration's scopes and role here.
#' The ODBC driver receives `authenticator = "oauth"` and the user's access token.
#' @inheritParams oauth_db_azure_sql
#' @param schema,warehouse,role Explicit Snowflake connection context.
#' @param scopes Scopes configured by the account's OAuth integration.
#' @param target Optional named shinyOAuth token target for external OAuth.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_snowflake <- function(
  authorization, server, database, schema, warehouse, role, ..., scopes,
  target = NULL, driver = "SnowflakeDSIIDriver", min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc")
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

.odb_backend_fabric <- function(token, service, provider_scopes, endpoint_hosts) {
  force(token)
  fabricQueryR::fabric_token_provider(
    token = function(audience, force_refresh = FALSE) token(force_refresh = force_refresh),
    services = service, scopes = stats::setNames(list(provider_scopes), service),
    endpoint_hosts = stats::setNames(list(endpoint_hosts), service))
}

.odb_backend_fabric_sql <- function(token, server, database, provider_scopes, endpoint_hosts, options) {
  force(token)
  provider <- fabricQueryR::fabric_token_provider(
    token = function(audience, force_refresh = FALSE) token(force_refresh = force_refresh),
    services = "sql", scopes = list(sql = provider_scopes),
    endpoint_hosts = list(sql = endpoint_hosts))
  do.call(fabricQueryR::fabric_sql_connect, c(list(server = server, database = database,
    token = provider, encrypt = "yes", trust_server_certificate = "no"), options))
}

.odb_backend_databricks <- function(token, host, warehouse_id, options) {
  provider <- brickster::db_token_provider(host, token)
  if (is.null(warehouse_id)) return(provider)
  do.call(DBI::dbConnect, c(list(drv = brickster::DatabricksSQL(), host = host,
    warehouse_id = warehouse_id, token = provider), options))
}

.odb_backend_snowflake <- function(token, server, database, schema, warehouse, role, driver, options) {
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver, server = server,
    database = database, schema = schema, warehouse = warehouse, role = role,
    authenticator = "oauth", token = token()), options))
}

.odb_backend_require_hook <- function(package, fun) {
  .odb_require(package)
  if (!fun %in% getNamespaceExports(package)) {
    .odb_abort(paste0("Install a version of ", package, " with the public ", fun,
      "() credential-provider API."), "unsupported_dependency")
  }
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
