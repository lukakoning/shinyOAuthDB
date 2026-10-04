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
  options <- .odb_options(list(...), blocked = c(
    "server", "database", "tenant_id", "client_id", "client_secret", "token",
    "access_token", "sql_token", "token_provider", "auth_args", "authentication",
    "authenticator", "user", "uid", "pwd", "password", "dsn", "drv", "attributes",
    ".connection_string", "connection_string", "trusted_connection",
    "integrated_security", "encrypt", "trust_server_certificate"))
  .odb_bind(authorization, .odb_backend_fabric_sql, server = server,
    database = database, provider_scopes = scopes,
    options = options, target = target, scopes = .odb_microsoft_scopes(scopes),
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
  target = .odb_fabric_profile(service)$target, scopes = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  service <- match.arg(service)
  profile <- .odb_fabric_profile(service)
  if (is.null(scopes)) scopes <- profile$scopes
  .odb_bind(authorization, .odb_backend_fabric, service = service,
    provider_scopes = scopes, target = target,
    scopes = .odb_microsoft_scopes(scopes), min_valid_for = min_valid_for, session = session)
}

.odb_backend_fabric <- function(token, service, provider_scopes) {
  force(token)
  allowed <- c(paste0(.odb_fabric_profile(service)$resource, "/.default"), provider_scopes)
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

.odb_fabric_profiles <- function() {
  list(
    fabric = .odb_microsoft_profile("fabric", "https://api.fabric.microsoft.com",
      c("Workspace.Read.All", "Item.Read.All")),
    dax = .odb_microsoft_profile("power_bi", "https://analysis.windows.net/powerbi/api", "Dataset.Read.All"),
    kql = .odb_microsoft_profile("kusto", "https://api.kusto.windows.net", "user_impersonation"),
    onelake = .odb_microsoft_profile("storage", "https://storage.azure.com", "user_impersonation"),
    graphql = .odb_microsoft_profile("power_bi", "https://analysis.windows.net/powerbi/api", "GraphQLApi.Execute.All")
  )
}

.odb_fabric_profile <- function(service) {
  profiles <- c(.odb_sql_server_profiles(), .odb_fabric_profiles())
  profile <- profiles[[service]]
  if (is.null(profile)) .odb_abort(paste0("Unknown Fabric service: ", service))
  profile
}
