#' Query Fabric SQL as the signed-in user
#'
#' Read data from a Fabric Warehouse, Lakehouse SQL analytics endpoint, or
#' SQL Database with DBI or dbplyr. Queries use the visitor's Microsoft account.
#'
#' @inheritParams oauth_db_azure_sql
#' @param ... Arguments for `fabricQueryR::fabric_sql_connect()`, such as
#'   `backend`, `read_only`, and `timeout`.
#' @return A reactive function returning a DBI connection.
#' @details
#' Install fabricQueryR and the SQL driver. Copy the server and database
#' from the item's SQL connection settings. Use [oauth_db_microsoft_client()]
#' with `services = "sql"` for sign-in.
#'
#' Create `con` inside `server()` and get `connection <- con()` inside a
#' render or reactive expression before querying. The helper reuses the
#' connection and closes it when the authorization or session ends.
#' @section SQL drivers:
#' The default backend uses odbc. To use ADBC, install fabricQueryR's ADBC
#' dependencies and the MSSQL driver, then pass `backend = "adbc"`.
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
#' @seealso [oauth_db_microsoft_client()], [oauth_db_fabric_api()].
#'   `vignette("fabric", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family database connections
#' @export
oauth_db_fabric_sql <- function(
  authorization,
  server,
  database = NULL,
  ...,
  target = "sql",
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("fabricQueryR", version = "1.0.1")
  options <- .odb_options(
    list(...),
    blocked = c(
      "server",
      "addr",
      "address",
      "database",
      "tenant_id",
      "client_id",
      "client_secret",
      "token",
      "access_token",
      "sql_token",
      "token_provider",
      "auth_args",
      "authentication",
      "authenticator",
      "user",
      "uid",
      "pwd",
      "password",
      "dsn",
      "filedsn",
      "savefile",
      "failover_partner",
      "drv",
      "attributes",
      ".connection_string",
      "connection_string",
      "trusted_connection",
      "integrated_security",
      "encrypt",
      "trust_server_certificate"
    ),
    partial = c("dsn", "tenant_id", "client_id", "auth_args")
  )
  .odb_odbc_values(options)
  .odb_bind(
    authorization,
    .odb_backend_fabric_sql,
    server = server,
    database = database,
    provider_scopes = required_scopes,
    options = options,
    target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    min_valid_for = min_valid_for,
    session = session
  )
}

#' Get a token callback for one Fabric service
#'
#' Use this to call a fabricQueryR function directly with the visitor's
#' credentials. It supplies the callback expected by the function's `token`
#' argument. For several services or resource objects, use
#' [oauth_db_fabric_api()].
#'
#' @inheritParams oauth_db_connect
#' @param service One of `"fabric"`, `"sql"`, `"dax"`, `"kql"`, `"onelake"`,
#'   or `"graphql"`.
#' @param target Token target name. Defaults to the service's preset target.
#'   Use `NULL` if the authorization has no named targets.
#' @param required_scopes Additional permissions to check. `NULL` uses the
#'   service's read/query defaults.
#' @return A reactive function. Call `callback()` to get the function to pass
#'   as fabricQueryR's `token` argument.
#' @details
#' Create the helper inside `server()`. The callback obtains and renews tokens
#' through shinyOAuth. It stays tied to the authorization that created it.
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
#' @seealso [oauth_db_fabric_api()].
#'   `vignette("fabric", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family advanced connection helpers
#' @export
oauth_db_fabric <- function(
  authorization,
  service = c("fabric", "sql", "dax", "kql", "onelake", "graphql"),
  target = .odb_fabric_profile(service)$target,
  required_scopes = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  service <- match.arg(service)
  profile <- .odb_fabric_profile(service)
  if (is.null(required_scopes)) {
    required_scopes <- profile$scopes
  }
  .odb_bind(
    authorization,
    .odb_backend_fabric,
    service = service,
    provider_scopes = required_scopes,
    target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    # Acquire before handing the callback to a native operation. Its identity
    # stays stable through rotation; later callback failures remain native errors.
    cache_key = function(token) {
      token()
      NULL
    },
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_fabric <- function(token, service, provider_scopes) {
  force(token)
  allowed <- c(
    paste0(.odb_fabric_profile(service)$resource, "/.default"),
    provider_scopes
  )
  force(allowed)
  function(audience, force_refresh = FALSE) {
    if (
      !is.character(audience) ||
        !length(audience) ||
        anyNA(audience) ||
        !all(audience %in% allowed)
    ) {
      .odb_abort(
        "The Fabric callback cannot supply tokens for this audience or scope.",
        "invalid_audience"
      )
    }
    token(force_refresh = force_refresh)
  }
}

.odb_backend_fabric_sql <- function(
  token,
  server,
  database,
  provider_scopes,
  options
) {
  provider <- .odb_backend_fabric(token, "sql", provider_scopes)
  do.call(
    fabricQueryR::fabric_sql_connect,
    c(
      list(
        server = server,
        database = database,
        token = provider,
        encrypt = "yes",
        trust_server_certificate = "no"
      ),
      options
    )
  )
}

#' Call Fabric functions as the signed-in user
#'
#' List workspaces, query semantic models, or read OneLake data through
#' fabricQueryR. Pass a function and its usual arguments to `$call()`;
#' the client supplies the visitor's credentials.
#'
#' @inheritParams oauth_db_connect
#' @param targets Named vector or list mapping services to shinyOAuth token
#'   targets. Defaults match [oauth_db_microsoft_client()]. A supplied mapping
#'   replaces the defaults. Use `list(kql = NULL)` for one service without
#'   a named target.
#' @param required_scopes Named list of additional permissions to check,
#'   by service. Set client and target requirements in shinyOAuth.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$call(.fn, ...)} calls a fabricQueryR function and returns
#'       its result, including resource objects. Omit \code{token} from
#'       the function arguments.
#'     \item \code{$token_provider()} returns a token callback for calling
#'       a fabricQueryR function directly.
#'   }
#' @details
#' Create the client inside `server()`. Configure
#' [oauth_db_microsoft_client()] for the services your app needs.
#' @section Resource objects:
#' fabricQueryR objects, such as a Lakehouse, keep the authorization used to
#' create them. Put the lookup in `reactive()` so a change of account obtains
#' a new object. The object's methods can then use the same sign-in.
#'
#' Use [oauth_db_fabric_sql()] for a DBI connection managed by shinyOAuthDB.
#' Your app must close connections it opens through fabricQueryR functions
#' or resource methods.
#' @section Custom token targets:
#' The `targets` mapping selects the services the client can use. DAX and
#' GraphQL share the Power BI resource and must use the same target;
#' different resources need different targets. Tokens are obtained only
#' when a service needs them.
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
#' @seealso [oauth_db_microsoft_client()], [oauth_db_fabric_sql()].
#'   `vignette("fabric", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family platform API clients
#' @export
oauth_db_fabric_api <- function(
  authorization,
  targets = list(
    fabric = "fabric",
    sql = "sql",
    dax = "power_bi",
    kql = "kusto",
    onelake = "storage",
    graphql = "power_bi"
  ),
  required_scopes = list(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("fabricQueryR", version = "1.0.1")
  read <- .odb_api_authorization(authorization, session)
  groups <- .odb_fabric_api_groups(targets, required_scopes)
  providers <- lapply(groups, function(group) {
    .odb_bind(
      authorization,
      identity,
      target = group$target,
      required_scopes = group$scopes,
      min_valid_for = min_valid_for,
      session = session
    )
  })
  .odb_fabric_api$new(read, providers, groups)
}

.odb_fabric_api <- R6::R6Class(
  "OAuthFabricAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(read, providers, groups) {
      private$read <- read
      private$providers <- providers
      private$groups <- groups
    },
    call = function(.fn, ...) {
      args <- .odb_api_arguments(
        .fn,
        list(...),
        blocked = c(
          "token",
          "access_token",
          "token_provider",
          "sql_token",
          "storage_token",
          "auth_args",
          "tenant_id",
          "client_id",
          "client_secret",
          "authentication",
          "authenticator",
          "user",
          "password"
        )
      )
      provider <- self$token_provider()
      do.call(.fn, c(args, list(token = provider)))
    },
    token_provider = function() {
      assert_current <- private$read(.pin = TRUE)
      # Resolve target callbacks on use so retained resources can recover
      # permissions while remaining bound to their original authorization.
      providers <- lapply(private$providers, function(accessor) {
        function(force_refresh = FALSE, scopes = character()) {
          assert_current()
          provider <- accessor()
          assert_current()
          provider(force_refresh = force_refresh, scopes = scopes)
        }
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
  if (is.character(targets)) {
    targets <- as.list(targets)
  }
  services <- names(c(.odb_sql_server_profiles(), .odb_fabric_profiles()))
  if (!is.list(targets) || !length(targets)) {
    .odb_abort("targets must map services to target names.")
  }
  .odb_named_args(targets, "targets")
  if (!all(names(targets) %in% services)) {
    .odb_abort("targets contains an unsupported Fabric service.")
  }
  for (target in targets) {
    .odb_string(target, "target name", optional = TRUE)
  }
  if (!is.list(required_scopes)) {
    .odb_abort("required_scopes must be a named list by service.")
  }
  .odb_named_args(required_scopes, "required_scopes")
  if (!all(names(required_scopes) %in% names(targets))) {
    .odb_abort("required_scopes must name services declared in targets.")
  }
  scopes <- lapply(required_scopes, .odb_microsoft_scopes)
  resources <- vapply(
    names(targets),
    function(service) .odb_fabric_profile(service)$resource,
    ""
  )
  groups <- lapply(unique(resources), function(resource) {
    selected <- names(targets)[resources == resource]
    target <- targets[[selected[[1L]]]]
    if (!all(vapply(targets[selected], identical, logical(1), target))) {
      .odb_abort(
        "Fabric services sharing a resource must select the same target."
      )
    }
    permissions <- unique(unlist(scopes[selected], use.names = FALSE))
    if (is.null(permissions)) {
      permissions <- character()
    }
    list(resource = resource, target = target, scopes = permissions)
  })
  target_names <- vapply(
    groups,
    function(group) if (is.null(group$target)) "" else group$target,
    ""
  )
  if (anyDuplicated(target_names)) {
    .odb_abort(
      "Different Fabric resources require different targets; NULL supports one resource only."
    )
  }
  groups
}

.odb_fabric_api_provider <- function(providers, groups) {
  force(providers)
  force(groups)
  function(audience, force_refresh = FALSE) {
    .odb_flag(force_refresh, "force_refresh")
    if (
      !is.character(audience) ||
        !length(audience) ||
        anyNA(audience) ||
        !all(nzchar(audience)) ||
        any(grepl("[[:space:]]", audience))
    ) {
      .odb_abort(
        "Supply an audience or scopes for one configured Fabric resource.",
        "invalid_audience"
      )
    }
    selected <- which(vapply(
      groups,
      function(group) {
        prefix <- paste0(group$resource, "/")
        permission <- substring(audience, nchar(prefix) + 1L)
        all(
          audience == group$resource |
            (startsWith(audience, prefix) &
              nzchar(permission) &
              !grepl("[/#?]", permission))
        )
      },
      logical(1)
    ))
    if (length(selected) != 1L) {
      .odb_abort(
        "The Fabric callback cannot supply tokens for this audience or scope.",
        "invalid_audience"
      )
    }
    index <- selected[[1L]]
    provider <- providers[[index]]
    if (inherits(provider, "condition")) {
      stop(provider)
    }
    scopes <- audience[
      audience != groups[[index]]$resource &
        audience != paste0(groups[[index]]$resource, "/.default")
    ]
    provider(force_refresh = force_refresh, scopes = scopes)
  }
}

.odb_fabric_profiles <- function() {
  list(
    fabric = .odb_microsoft_profile(
      "fabric",
      "https://api.fabric.microsoft.com",
      c("Workspace.Read.All", "Item.Read.All")
    ),
    dax = .odb_microsoft_profile(
      "power_bi",
      "https://analysis.windows.net/powerbi/api",
      "Dataset.Read.All"
    ),
    kql = .odb_microsoft_profile(
      "kusto",
      "https://api.kusto.windows.net",
      "user_impersonation"
    ),
    onelake = .odb_microsoft_profile(
      "storage",
      "https://storage.azure.com",
      "user_impersonation"
    ),
    graphql = .odb_microsoft_profile(
      "power_bi",
      "https://analysis.windows.net/powerbi/api",
      "GraphQLApi.Execute.All"
    )
  )
}

.odb_fabric_profile <- function(service) {
  profiles <- c(.odb_sql_server_profiles(), .odb_fabric_profiles())
  profile <- profiles[[service]]
  if (is.null(profile)) {
    .odb_abort(paste0("Unknown Fabric service: ", service))
  }
  profile
}
