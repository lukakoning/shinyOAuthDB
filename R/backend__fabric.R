#' Use the user's authorization with Fabric SQL
#'
#' Delegates connection details and the ODBC or ADBC transport to
#' `fabricQueryR::fabric_sql_connect()`. Pass its native options such as
#' `backend`, `odbc_driver`, `read_only`, and `timeout` in `...`.
#' @inheritParams oauth_db_azure_sql
#' @returns A session-local reactive accessor for a native DBI connection.
#' @seealso [oauth_db_fabric_api()], [oauth_db_fabric()], [oauth_db_microsoft_client()]
#' @examples
#' \dontrun{
#' # Inside server(); configure the Microsoft client with services = "sql".
#' con <- oauth_db_fabric_sql(auth$connection,
#'   server = "example.datawarehouse.fabric.microsoft.com", database = "Sales")
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT TOP (10) name FROM sys.tables")
#' })
#' }
#' @export
oauth_db_fabric_sql <- function(
  authorization, server, database = NULL, ..., target = "sql",
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("fabricQueryR", version = "1.0.1")
  options <- .odb_options(list(...), blocked = c(
    "server", "database", "tenant_id", "client_id", "client_secret", "token",
    "access_token", "sql_token", "token_provider", "auth_args", "authentication",
    "authenticator", "user", "uid", "pwd", "password", "dsn", "drv", "attributes",
    ".connection_string", "connection_string", "trusted_connection",
    "integrated_security", "encrypt", "trust_server_certificate"))
  .odb_bind(authorization, .odb_backend_fabric_sql, server = server,
    database = database, provider_scopes = required_scopes,
    options = options, target = target, required_scopes = .odb_microsoft_scopes(required_scopes),
    min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with native Fabric functions
#'
#' Create a `callback` accessor, then pass `callback()` to fabricQueryR's `token`
#' argument. That value is an ordinary credential callback for the native API.
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
#' @param required_scopes Delegated scopes; `NULL` uses the service's query/read defaults.
#' @returns A session-local reactive accessor for a native token provider.
#' @seealso [oauth_db_fabric_api()], [oauth_db_fabric_sql()], [oauth_db_microsoft_client()]
#' @examples
#' \dontrun{
#' # Inside server(); configure the Microsoft client with services = "kql".
#' callback <- oauth_db_fabric(auth$connection, service = "kql")
#' output$rows <- shiny::renderTable({
#'   fabricQueryR::fabric_kql_query(
#'     cluster = "https://example.kusto.fabric.microsoft.com",
#'     database = "Events", query = "Events | take 10", token = callback())
#' })
#' }
#' @export
oauth_db_fabric <- function(
  authorization, service = c("fabric", "sql", "dax", "kql", "onelake", "graphql"),
  target = .odb_fabric_profile(service)$target, required_scopes = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  service <- match.arg(service)
  profile <- .odb_fabric_profile(service)
  if (is.null(required_scopes)) required_scopes <- profile$scopes
  .odb_bind(authorization, .odb_backend_fabric, service = service,
    provider_scopes = required_scopes, target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    # Acquire before handing the callback to a native operation. Its identity
    # stays stable through rotation; later callback failures remain native errors.
    cache_key = function(token) { token(); NULL },
    min_valid_for = min_valid_for, session = session)
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

#' Call native Fabric functions and reuse their resource objects
#'
#' Create this client once inside `server()`. Use `$call(.fn, ...)` to supply
#' an audience-aware callback to fabricQueryR's ordinary `token` argument.
#' Discovery returns native fabricQueryR R6 objects; their methods retain that
#' callback and can obtain different service tokens from the same authorization.
#' @inheritParams oauth_db_connect
#' @param targets Named character vector or list mapping Fabric services to
#'   shinyOAuth target names. Defaults match [oauth_db_microsoft_client()].
#'   Supply a subset to allow only those services. Use `list(kql = NULL)` for
#'   a single-resource client without named targets. Services sharing a resource
#'   (DAX and GraphQL) must select the same target; different resources require
#'   different targets. Missing targets fail only when their service is used.
#' @param required_scopes Named list of additional permissions by service,
#'   empty by default. Client and target requirements remain enforced by
#'   shinyOAuth. Explicit scopes requested by the native callback are also checked.
#' @return An R6 `OAuthFabricAPI` with `$call(.fn, ...)`, `$token_provider()`
#'   and `$print()`. `$token_provider()` returns an ordinary
#'   `function(audience, force_refresh = FALSE)` for native calls.
#' @details
#' A provider is pinned to the authorization selected when it was created. It
#' can refresh tokens within that authorization, but cannot adopt a later login
#' or another selection. The callback accepts configured resource identifiers,
#' their `/.default` audience, or fully qualified scopes for one resource at a
#' time. Resource identifiers are matched literally, including trailing slashes.
#'
#' The bridge adds no query methods, function registry, result cache, or retries.
#' Native functions retain their arguments, return values, errors and transport
#' behavior. Native DBI connections opened through `$call()` or a resource's
#' `$sql_connect()` belong to the application; [oauth_db_fabric_sql()] supplies
#' session-managed DBI connections instead. Resource objects and callbacks run
#' in the owning Shiny session, not in background workers. App-owned caches
#' and background results need their own authorization guards.
#' @examples
#' \dontrun{
#' # Configure the Microsoft client with services = c("fabric", "sql", "onelake").
#' # Inside server():
#' fabric <- oauth_db_fabric_api(auth$connection)
#' lakehouse <- shiny::reactive({
#'   fabric$call(fabricQueryR::fabric_item,
#'     workspace = "workspace-guid", item = "lakehouse-guid")
#' })
#' output$rows <- shiny::renderTable({
#'   lakehouse()$read_table("Orders", limit = 100L)
#' })
#' # Or pass the callback to a native function directly:
#' output$workspaces <- shiny::renderPrint({
#'   fabricQueryR::fabric_workspaces(token = fabric$token_provider())
#' })
#' }
#' @export
oauth_db_fabric_api <- function(
  authorization,
  targets = list(fabric = "fabric", sql = "sql", dax = "power_bi",
                 kql = "kusto", onelake = "storage", graphql = "power_bi"),
  required_scopes = list(), min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("fabricQueryR", version = "1.0.1")
  read <- .odb_api_authorization(authorization, session)
  groups <- .odb_fabric_api_groups(targets, required_scopes)
  providers <- lapply(groups, function(group) {
    .odb_bind(authorization, identity, target = group$target,
      required_scopes = group$scopes, min_valid_for = min_valid_for, session = session)
  })
  .odb_fabric_api$new(read, providers, groups)
}

.odb_fabric_api <- R6::R6Class("OAuthFabricAPI", cloneable = FALSE,
  public = list(
    initialize = function(read, providers, groups) {
      private$read <- read
      private$providers <- providers
      private$groups <- groups
    },
    call = function(.fn, ...) {
      args <- .odb_api_arguments(.fn, list(...), blocked = c(
        "token", "access_token", "token_provider", "sql_token", "storage_token",
        "auth_args", "tenant_id", "client_id", "client_secret", "authentication",
        "authenticator", "user", "password"))
      provider <- self$token_provider()
      do.call(.fn, c(args, list(token = provider)))
    },
    token_provider = function() {
      private$read()
      # Capture all grant-pinned callbacks without acquiring their tokens.
      # Optional/missing targets remain lazy until a native request needs one.
      providers <- lapply(private$providers, function(accessor) {
        tryCatch(accessor(), error = identity)
      })
      .odb_fabric_api_provider(providers, private$groups)
    },
    print = function(...) {
      cat("<OAuthFabricAPI>\n")
      invisible(self)
    }
  ),
  private = list(read = NULL, providers = NULL, groups = NULL)
)

.odb_fabric_api_groups <- function(targets, required_scopes) {
  if (is.character(targets)) targets <- as.list(targets)
  services <- names(c(.odb_sql_server_profiles(), .odb_fabric_profiles()))
  if (!is.list(targets) || !length(targets)) .odb_abort("targets must map services to target names.")
  .odb_named_args(targets, "targets")
  if (!all(names(targets) %in% services)) .odb_abort("targets contains an unsupported Fabric service.")
  for (target in targets) .odb_string(target, "target name", optional = TRUE)
  if (!is.list(required_scopes)) .odb_abort("required_scopes must be a named list by service.")
  .odb_named_args(required_scopes, "required_scopes")
  if (!all(names(required_scopes) %in% names(targets))) {
    .odb_abort("required_scopes must name services declared in targets.")
  }
  scopes <- lapply(required_scopes, .odb_microsoft_scopes)
  resources <- vapply(names(targets), function(service) .odb_fabric_profile(service)$resource, "")
  groups <- lapply(unique(resources), function(resource) {
    selected <- names(targets)[resources == resource]
    target <- targets[[selected[[1L]]]]
    if (!all(vapply(targets[selected], identical, logical(1), target))) {
      .odb_abort("Fabric services sharing a resource must select the same target.")
    }
    permissions <- unique(unlist(scopes[selected], use.names = FALSE))
    if (is.null(permissions)) permissions <- character()
    list(resource = resource, target = target, scopes = permissions)
  })
  target_names <- vapply(groups, function(group) if (is.null(group$target)) "" else group$target, "")
  if (anyDuplicated(target_names)) {
    .odb_abort("Different Fabric resources require different targets; NULL supports one resource only.")
  }
  groups
}

.odb_fabric_api_provider <- function(providers, groups) {
  force(providers)
  force(groups)
  function(audience, force_refresh = FALSE) {
    .odb_flag(force_refresh, "force_refresh")
    if (!is.character(audience) || !length(audience) || anyNA(audience) ||
        any(!nzchar(audience)) || any(grepl("[[:space:]]", audience))) {
      .odb_abort("Supply an audience or scopes for one configured Fabric resource.", "invalid_audience")
    }
    selected <- which(vapply(groups, function(group) {
      prefix <- paste0(group$resource, "/")
      permission <- substring(audience, nchar(prefix) + 1L)
      all(audience == group$resource |
        (startsWith(audience, prefix) & nzchar(permission) & !grepl("[/#?]", permission)))
    }, logical(1)))
    if (length(selected) != 1L) {
      .odb_abort("The Fabric callback cannot supply tokens for this audience or scope.", "invalid_audience")
    }
    index <- selected[[1L]]
    provider <- providers[[index]]
    if (inherits(provider, "condition")) stop(provider)
    scopes <- audience[audience != groups[[index]]$resource &
      audience != paste0(groups[[index]]$resource, "/.default")]
    provider(force_refresh = force_refresh, scopes = scopes)
  }
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
