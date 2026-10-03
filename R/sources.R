.odb_source_error <- function(message, reason = "invalid_configuration") {
  .odb_abort(message, reason)
}

.odb_source_string <- function(x, name, nullable = FALSE) {
  if (nullable && is.null(x)) return(invisible(NULL))
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    .odb_source_error(paste0(name, " must be one non-empty string."))
  }
  invisible(x)
}

.odb_source_host <- function(x, name = "server") {
  .odb_source_string(x, name)
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", x)) {
    .odb_source_error(paste0(name, " must be a hostname without a URL, port or connection string."))
  }
  tolower(x)
}

.odb_source_origin <- function(x, name = "host") {
  .odb_source_string(x, name)
  if (!grepl("://", x, fixed = TRUE)) x <- paste0("https://", x)
  if (!grepl("^https://[A-Za-z0-9][A-Za-z0-9.-]*/?$", x)) {
    .odb_source_error(paste0(name, " must be an HTTPS origin without credentials, ports or paths."))
  }
  sub("/$", "", tolower(x))
}

.odb_source_port <- function(x) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x != as.integer(x) || x < 1 || x > 65535) {
    .odb_source_error("port must be an integer between 1 and 65535.")
  }
  as.integer(x)
}

.odb_source_odbc_value <- function(value) {
  if (is.character(value) && any(grepl("[;={}[:cntrl:]]|^[[:space:]]|[[:space:]]$", value))) {
    .odb_source_error("ODBC values cannot contain connection-string delimiters, control characters or outer whitespace. Supply separate source fields using ordinary names.")
  }
  invisible(value)
}

.odb_source_odbc_options <- function(options, allowed) {
  options <- .odb_source_options(options, allowed)
  for (value in options) .odb_source_odbc_value(value)
  options
}

.odb_source_bearer <- function(token) {
  .odb_source_string(token, "acquired access token")
  if (!grepl("^[A-Za-z0-9._~+/-]+=*$", token)) {
    .odb_source_error("The acquired bearer credential contains invalid characters.", "invalid_credential")
  }
  invisible(token)
}

.odb_source_options <- function(options, allowed) {
  if (!is.list(options) || (length(options) &&
      (is.null(names(options)) || anyNA(names(options)) || any(!nzchar(names(options))) ||
       anyDuplicated(tolower(names(options))) || !all(names(options) %in% allowed)))) {
    .odb_source_error(paste0("options must be a named list selecting: ", paste(allowed, collapse = ", "),
                            ". Credentials, endpoints and alternate authentication cannot be overridden."))
  }
  if (any(vapply(options, function(x) !is.atomic(x) || length(x) != 1L || is.na(x), logical(1)))) {
    .odb_source_error("Each connection option must be one non-missing atomic value.")
  }
  options
}

.odb_source_scopes <- function(scopes, resource, required_scopes = scopes) {
  for (value in list(scopes, required_scopes)) {
    if (!is.character(value) || anyNA(value) || any(!nzchar(value)) || any(grepl("[[:space:]?#]", value))) {
      .odb_source_error("scopes and required_scopes must be character vectors of OAuth scopes.")
    }
  }
  if (length(scopes) && !is.null(resource) && !all(startsWith(scopes, paste0(resource, "/")))) {
    .odb_source_error("Every scope must be fully qualified with this source's exact resource.")
  }
  if (!all(required_scopes %in% scopes) || any(endsWith(required_scopes, "/.default"))) {
    .odb_source_error("required_scopes must select explicit permissions from scopes; .default is a consent profile.")
  }
  list(scopes = unique(scopes), required_scopes = unique(required_scopes))
}

.odb_source_identity <- function(value) {
  if (is.function(value)) {
    # Never serialize a hook's closure: it may capture app/session credentials.
    return(list(formals = deparse(formals(value)), body = deparse(body(value)),
                environment = format(environment(value))))
  }
  if (is.list(value)) return(lapply(value, .odb_source_identity))
  value
}

.odb_new_source <- function(backend, config, provider_family, target, resource, scopes,
                            required_scopes = scopes, capabilities = list(),
                            protected_args = character(), adapter = NULL) {
  .odb_source_string(backend, "backend")
  .odb_source_string(provider_family, "provider_family")
  .odb_source_string(target, "target", nullable = TRUE)
  .odb_source_string(resource, "resource", nullable = TRUE)
  profile <- .odb_source_scopes(scopes, resource, required_scopes)
  auth <- c(list(provider_family = provider_family, target = target, resource = resource), profile)
  value <- list(backend = backend, config = config, auth = auth,
                capabilities = capabilities, protected_args = unique(protected_args))
  if (!is.null(adapter)) value$adapter <- adapter
  value$id <- paste0(backend, ":", digest::digest(.odb_source_identity(value), algo = "sha256"))
  structure(value[c("id", setdiff(names(value), "id"))], class = "oauth_db_source")
}

.odb_validate_source <- function(source) {
  if (!inherits(source, "oauth_db_source") || !is.list(source) ||
      !all(c("id", "backend", "config", "auth", "capabilities", "protected_args") %in% names(source))) {
    .odb_source_error("source must be an oauth_db_source constructor result.")
  }
  invisible(source)
}

.odb_sql_capabilities <- function(package, transactions = TRUE, strategy = "worker_connection") {
  list(native_dbi = TRUE, sql = TRUE, transactions = transactions,
       async_strategy = strategy, connector_package = package,
       connection_reuse = "session", token_refresh = "new_connection",
       query_deadline = FALSE, remote_cancellation = FALSE,
       delegated_user = TRUE, live_verified = FALSE)
}

.odb_sql_protected <- c("conn", "connection", "drv", "driver", "server", "host", "port", "database",
  "dbname", "user", "uid", "pwd", "password", "token", "token_provider", "attributes", "dsn",
  ".connection_string", "connection_string", "authentication", "authenticator", "auth_args",
  "trusted_connection", "integrated_security", "encrypt", "sslmode", "sslrootcert",
  "trustservercertificate", "token_file_path", "role", "warehouse", "schema", "catalog")

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
oauth_db_azure_sql <- function(server, database, target = "sql",
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  scopes = "https://database.windows.net//user_impersonation", options = list()) {
  .odb_source_string(database, "database")
  .odb_source_string(driver, "driver")
  .odb_source_odbc_value(database)
  .odb_source_odbc_value(driver)
  config <- list(server = .odb_source_host(server), database = database,
                 driver = driver, port = .odb_source_port(port),
                 options = .odb_source_odbc_options(options, c("timezone", "timezone_out", "encoding",
                   "name_encoding", "bigint", "timeout", "interruptible", "ApplicationIntent")))
  .odb_new_source("azure_sql", config, "microsoft", target,
    "https://database.windows.net/", scopes, capabilities = .odb_sql_capabilities("odbc"),
    protected_args = .odb_sql_protected)
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
oauth_db_sql_server <- function(server, database, entra_enabled = FALSE, target = "sql",
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  scopes = "https://database.windows.net//user_impersonation", options = list()) {
  if (!identical(entra_enabled, TRUE)) {
    .odb_source_error("SQL Server needs configured native Entra authentication. Set entra_enabled = TRUE only after that setup; ordinary SQL/Windows authentication cannot reuse the app visitor's OAuth identity.", "unsupported_authentication")
  }
  source <- oauth_db_azure_sql(server, database, target, driver, port, scopes, options)
  .odb_new_source("sql_server", c(source$config, list(entra_enabled = TRUE)), "microsoft", target,
    source$auth$resource, scopes, capabilities = source$capabilities, protected_args = source$protected_args)
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
oauth_db_azure_postgres <- function(host, database, user, target = "postgres", port = 5432L,
  sslrootcert = NULL, resource = "https://ossrdbms-aad.database.windows.net",
  scopes = paste0(resource, "/.default"),
  required_scopes = if (any(endsWith(scopes, "/.default"))) character() else scopes,
  options = list()) {
  for (name in c("database", "user")) .odb_source_string(get(name), name)
  .odb_source_string(sslrootcert, "sslrootcert", nullable = TRUE)
  config <- list(host = .odb_source_host(host, "host"), database = database, user = user,
    port = .odb_source_port(port), sslrootcert = sslrootcert,
    options = .odb_source_options(options, c("connect_timeout", "application_name", "bigint",
      "check_interrupts", "timezone", "timezone_out")))
  capabilities <- .odb_sql_capabilities("RPostgres")
  capabilities$transaction_caveat <- "A broken connection can be reset by libpq; no transaction replay is provided"
  capabilities$native_reconnect <- "libpq may reset a broken connection with the original token"
  .odb_new_source("azure_postgres", config, "microsoft", target, resource, scopes, required_scopes,
    capabilities, .odb_sql_protected)
}

#' Describe a Databricks workspace or SQL warehouse
#'
#' The native brickster token provider enforces exact workspace binding. Native
#' Databricks OAuth and Entra are separate profiles; neither falls back to the
#' app host's CLI, environment, PAT or service-principal credentials.
#' @param host Workspace hostname or HTTPS origin.
#' @param warehouse_id SQL warehouse ID, or `NULL` for non-SQL REST operations.
#' @param catalog,schema Optional default SQL namespace.
#' @param auth_mode `"databricks_oauth"` or Azure Databricks `"entra"`.
#' @param target Declared shinyOAuth token-target name.
#' @param scopes Delegated scope profile; default `all-apis` for native OAuth.
#' @param options Native brickster connection options.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_databricks <- function(host, warehouse_id = NULL, catalog = NULL, schema = NULL,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL, scopes = NULL,
  options = list()) {
  auth_mode <- match.arg(auth_mode)
  host <- .odb_source_origin(host)
  for (name in c("warehouse_id", "catalog", "schema")) .odb_source_string(get(name), name, TRUE)
  resource <- if (auth_mode == "entra") "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" else NULL
  if (is.null(scopes)) scopes <- if (auth_mode == "entra") paste0(resource, "/user_impersonation") else "all-apis"
  config <- list(host = host, warehouse_id = warehouse_id, catalog = catalog, schema = schema,
    auth_mode = auth_mode, options = .odb_source_options(options,
      c("disposition", "max_active_connections", "fetch_timeout", "show_progress", "staging_volume")))
  capabilities <- .odb_sql_capabilities("brickster", transactions = FALSE)
  capabilities$native_dbi <- capabilities$sql <- !is.null(warehouse_id)
  capabilities$token_refresh <- "per_request"
  .odb_new_source("databricks", config,
    if (auth_mode == "entra") "microsoft" else "databricks", target, resource, scopes,
    capabilities = capabilities, protected_args = c(.odb_sql_protected, "warehouse_id", "http_path", "staging_volume", "perform_request"))
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
oauth_db_snowflake <- function(server, database, schema, warehouse, role,
  driver = "SnowflakeDSIIDriver", auth_mode = c("external_oauth", "snowflake_oauth"),
  provider_family = NULL, resource = NULL, scopes, required_scopes = scopes,
  target = if (auth_mode[[1L]] == "snowflake_oauth") NULL else "snowflake", options = list()) {
  auth_mode <- match.arg(auth_mode)
  for (name in c("database", "schema", "warehouse", "role", "driver")) {
    .odb_source_string(get(name), name)
    .odb_source_odbc_value(get(name))
  }
  if (auth_mode == "snowflake_oauth") {
    if (!is.null(provider_family) && provider_family != "snowflake") .odb_source_error("Native Snowflake OAuth requires provider_family = 'snowflake'.")
    provider_family <- "snowflake"
  } else {
    .odb_source_string(provider_family, "provider_family")
    .odb_source_string(resource, "resource")
  }
  config <- list(server = .odb_source_host(server), database = database, schema = schema,
    warehouse = warehouse, role = role, driver = driver, auth_mode = auth_mode,
    options = .odb_source_odbc_options(options, c("timezone", "timezone_out", "bigint", "timeout", "interruptible")))
  .odb_new_source("snowflake", config, provider_family, target, resource, scopes, required_scopes,
    .odb_sql_capabilities("odbc"), c(.odb_sql_protected, "auth_mode", "oauth_client_id", "oauth_client_secret", "oauth_scope"))
}

#' Describe a custom delegated database adapter
#'
#' Supply trusted application connectors rather than introducing another query
#' engine. A connector receives `config` and `token_provider`; it must use only
#' the supplied credential and return a native DBI connection. Closures are for
#' synchronous use; background work requires portable namespace functions.
#' Portable descriptors have deterministic IDs. A closure-backed custom source
#' uses the hook's process-local environment identity without serializing its
#' captured values; its ID need not persist across R processes.
#' @param backend Adapter name.
#' @param connect Function accepting `config` and `token_provider`, or portable
#'   native specification `list(package, fun, driver = list(package, fun),
#'   credential_arg = "password")`. `credential_arg` receives the supplied
#'   scalar user token. Without it the specification is a credential-free
#'   transport, useful for offline fixtures, and does not claim delegated access.
#' @param disconnect Function accepting the native connection.
#' @param token_provider Optional function accepting `source` and
#'   `credential_fun`, adapting it to a native credential provider.
#' @param config Non-secret connector configuration.
#' @param target,resource,scopes,required_scopes,provider_family OAuth profile.
#' @param capabilities Adapter capability overrides.
#' @param bindings Additional protected connector configuration for tasks.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_custom <- function(backend, connect, disconnect = DBI::dbDisconnect,
  token_provider = NULL, config = list(), target = NULL, resource = NULL,
  scopes = character(), required_scopes = scopes, provider_family = "custom",
  capabilities = list(), bindings = list()) {
  if ((!is.function(connect) && !is.list(connect)) || !is.function(disconnect) ||
      (!is.null(token_provider) && !is.function(token_provider))) {
    .odb_source_error("Custom connect/disconnect/token_provider hooks must be functions.")
  }
  if (is.function(connect) && !all(c("config", "token_provider") %in% names(formals(connect)))) {
    .odb_source_error("Custom connect must accept config and token_provider arguments explicitly.")
  }
  if (!is.list(config) || !is.list(capabilities) || !is.list(bindings)) {
    .odb_source_error("config, capabilities and bindings must be lists.")
  }
  .odb_source_custom_config(config)
  .odb_source_custom_config(bindings)
  caps <- utils::modifyList(.odb_sql_capabilities("custom"), capabilities)
  if (is.list(connect)) {
    for (spec in list(connect, connect$driver)) {
      if (!is.list(spec)) .odb_source_error("A portable connector needs package, fun and a driver specification.")
      .odb_source_string(spec$package, "connector package")
      .odb_source_string(spec$fun, "connector function")
    }
    .odb_source_string(connect$credential_arg, "credential_arg", nullable = TRUE)
    if (!is.null(connect$credential_arg) && connect$credential_arg %in% names(config)) {
      .odb_source_error("Portable credential_arg is supplied by the broker and cannot also appear in config.")
    }
    if (!is.null(connect$credential_arg) && connect$credential_arg %in% c("drv", "driver", "host", "server", "port", "database", "dbname")) {
      .odb_source_error("credential_arg must name the native connector's credential argument, not a driver or endpoint argument.")
    }
    caps$delegated_user <- !is.null(connect$credential_arg)
    caps$credential_transport <- if (caps$delegated_user) "explicit_scalar_credential" else "credential_free_fixture"
  }
  if (identical(disconnect, DBI::dbDisconnect)) disconnect <- list(package = "DBI", fun = "dbDisconnect")
  .odb_new_source(backend, config, provider_family, target, resource, scopes, required_scopes,
    caps, c(.odb_sql_protected, names(bindings)),
    list(connect = connect, disconnect = disconnect, token_provider = token_provider, bindings = bindings))
}

.odb_source_custom_config <- function(value, depth = 0L) {
  if (depth >= 50L || is.environment(value) || is.function(value) || isS4(value) ||
      typeof(value) %in% c("externalptr", "weakref", "symbol", "language", "pairlist")) {
    .odb_source_error("Custom configuration and bindings must contain plain non-secret data, without functions, environments or live objects.")
  }
  if (is.list(value)) {
    key <- tolower(gsub("[._ -]", "", names(value)))
    forbidden <- c("password", "pwd", "token", "tokens", "accesstoken", "refreshtoken", "idtoken",
      "clientsecret", "secret", "clientassertion", "privatekey", "privatekeyfile", "privatekeypath",
      "tokenfilepath", "connectionstring", "connstr", "authorization", "bearer", "apikey",
      "awsaccesskeyid", "awssecretaccesskey", "awssessiontoken")
    if (any(key %in% forbidden)) {
      .odb_source_error("Custom configuration and bindings cannot contain credentials or connection strings. Obtain credentials through the supplied token provider.")
    }
    for (element in value) .odb_source_custom_config(element, depth + 1L)
  }
  attributes <- attributes(value)
  if (!is.null(attributes)) {
    for (attribute in attributes) .odb_source_custom_config(attribute, depth + 1L)
  }
  invisible(value)
}

#' Inspect a source's backend capabilities
#' @param source An `oauth_db_source` descriptor.
#' @returns A list of declared capabilities, installation status and limitations.
#'   Availability does not prove live database access.
#' @export
oauth_db_capabilities <- function(source) {
  .odb_validate_source(source)
  package <- source$capabilities$connector_package
  installed <- identical(package, "custom") || requireNamespace(package, quietly = TRUE)
  c(source$capabilities, list(dependency_installed = installed,
    source_id = source$id, target = source$auth$target))
}

#' @export
print.oauth_db_source <- function(x, ...) {
  cat("<oauth_db_source:", x$backend, ">\n", sep = "")
  cat("  Target:", x$auth$target, "\n  Native DBI:", isTRUE(x$capabilities$native_dbi), "\n")
  invisible(x)
}
