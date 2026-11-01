#' Query Fabric SQL as the signed-in user
#'
#' Use DBI or dbplyr to query a Fabric Warehouse, Lakehouse SQL analytics
#' endpoint, or SQL Database. Supply the server and database from the item's
#' SQL connection settings.
#'
#' @inheritParams oauth_db_azure_sql
#' @param ... Options for `fabricQueryR::fabric_sql_connect()`, such as
#'   `backend`, `read_only`, and `timeout`.
#' @return A reactive function returning a DBI connection.
#' @details
#' Install fabricQueryR and the chosen SQL driver. Configure the Microsoft
#' client with `services = "sql"`. The default backend uses odbc; pass
#' `backend = "adbc"` to use ADBC after installing its dependencies.
#'
#' Create the helper in `server()`. Connections open on first use, are reused
#' for later operations, and close on sign-out or session end.
#' @examples
#' \dontrun{
#' con <- oauth_db_fabric_sql(
#'   auth$connection,
#'   server = "example.datawarehouse.fabric.microsoft.com",
#'   database = "Reporting"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT TOP (20) name FROM sys.tables")
#' })
#' }
#' @seealso [oauth_db_microsoft_client()], [oauth_db_fabric_api()]
#' @family database connections
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

#' Supply a token callback for one Fabric service
#'
#' Use this when calling a fabricQueryR function directly and you need a token
#' callback for one service. For an app using several Fabric services or
#' resource objects, use [oauth_db_fabric_api()].
#'
#' @inheritParams oauth_db_connect
#' @param service One of `"fabric"`, `"sql"`, `"dax"`, `"kql"`, `"onelake"`,
#'   or `"graphql"`.
#' @param target Token target name. Defaults to the service's preset target.
#'   Use `NULL` for an authorization without named targets.
#' @param required_scopes Extra permissions to check. `NULL` uses the service's
#'   read/query defaults.
#' @return A reactive function. Calling `callback()` returns a token-provider
#'   function for fabricQueryR's `token` argument.
#' @details
#' Create the helper inside `server()`. Its callback renews tokens through
#' shinyOAuth and remains tied to the authorization that created it.
#' @examples
#' \dontrun{
#' # Microsoft client configured with services = "kql":
#' callback <- oauth_db_fabric(auth$connection, service = "kql")
#' output$rows <- shiny::renderTable({
#'   fabricQueryR::fabric_kql_query(
#'     cluster = "https://example.kusto.fabric.microsoft.com",
#'     database = "Events",
#'     query = "Events | take 20",
#'     token = callback()
#'   )
#' })
#' }
#' @seealso [oauth_db_fabric_api()]
#' @family advanced connection helpers
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

#' Use Fabric functions and resource objects as the signed-in user
#'
#' Browse workspaces, query semantic models, or read OneLake data with
#' fabricQueryR. This client supplies the user's credentials to the package's
#' functions and to the resource objects they return.
#'
#' @inheritParams oauth_db_connect
#' @param targets Named vector or list mapping services to shinyOAuth target
#'   names. Defaults match [oauth_db_microsoft_client()]. A supplied mapping
#'   replaces the defaults. Use `list(kql = NULL)` for a single service without
#'   named targets.
#' @param required_scopes Named list of extra permissions to check by service.
#'   Client and target requirements remain configured in shinyOAuth.
#' @return An R6 client with two methods:
#'   \itemize{
#'     \item `$call(.fn, ...)` calls a fabricQueryR function with the user's
#'       authentication and returns its result. Leave `token` out of `...`.
#'     \item `$token_provider()` returns a callback for a direct native call's
#'       `token` argument.
#'   }
#' @details
#' Create the client inside `server()` and configure the Microsoft sign-in
#' client for the services your app needs. fabricQueryR's own R6 objects keep
#' the callback for later methods, including methods that need a different
#' service token.
#'
#' Discovered objects stay tied to their original authorization. Put discovery
#' in a reactive expression to recreate them when the selected account changes.
#' For a DBI connection managed by shinyOAuthDB, use [oauth_db_fabric_sql()].
#' Connections opened by native functions or resource methods belong to your app.
#'
#' For custom target names, see
#' `vignette("authorization", package = "shinyOAuthDB")`. DAX and GraphQL
#' share a resource and must map to the same target; different resources need
#' different targets. An unused target's token is obtained only when needed.
#' @examples
#' \dontrun{
#' # Microsoft client configured with services = c("fabric", "onelake"):
#' fabric <- oauth_db_fabric_api(auth$connection)
#' lakehouse <- shiny::reactive({
#'   fabric$call(
#'     fabricQueryR::fabric_item,
#'     workspace = "workspace-guid",
#'     item = "lakehouse-guid"
#'   )
#' })
#' output$rows <- shiny::renderTable({
#'   lakehouse()$read_table("Orders", limit = 100L)
#' })
#' }
#' @seealso [oauth_db_microsoft_client()], [oauth_db_fabric_sql()]
#' @family platform API clients
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
