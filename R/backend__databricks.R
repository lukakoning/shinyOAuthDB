#' Query Databricks SQL as the signed-in user
#'
#' Query Databricks tables with each visitor's account and data permissions.
#' You connect to a SQL warehouse, which supplies the compute for queries.
#' The connection works with DBI or dbplyr through the brickster package.
#'
#' @inheritParams oauth_db_connect
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param warehouse_id SQL warehouse ID. Supply this or `http_path`.
#' @param http_path Warehouse HTTP path, such as
#'   `"/sql/1.0/warehouses/warehouse-id"`. Supply this or `warehouse_id`.
#' @param ... brickster connection options, such as `catalog` and `schema`.
#' @param auth_mode `"databricks_oauth"`, or `"entra"` for Azure Databricks
#'   with Microsoft sign-in.
#' @param target Token target name. Defaults to `"databricks"` for Entra.
#'   Databricks OAuth uses the authorization's default token.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install brickster and use [oauth_db_databricks_client()] for Databricks
#' sign-in. The user needs access to the workspace, SQL warehouse and data.
#' For Azure Databricks with Entra, use [oauth_db_microsoft_client()] with
#' `services = "databricks_entra"` and set `auth_mode = "entra"` here.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' Use [oauth_db_databricks_api()] to call other brickster functions.
#' @section Connection lifetime:
#' The helper replaces the connection when its token changes. A saved
#' brickster connection can retain its old token after sign-out, so obtain
#' the current connection through `con()` for every operation.
#' @examples
#' \dontrun{
#' con <- oauth_db_databricks(
#'   auth$connection,
#'   host = "example.cloud.databricks.com",
#'   warehouse_id = "warehouse-id"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user()")
#' })
#' }
#' @seealso [oauth_db_databricks_client()], [oauth_db_databricks_api()].
#'   `vignette("databricks", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_databricks <- function(
  authorization,
  host,
  warehouse_id = NULL,
  ...,
  http_path = NULL,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  if (auth_mode == "entra") {
    required_scopes <- .odb_microsoft_scopes(required_scopes)
  }
  if (missing(host)) {
    .odb_abort(
      "Supply host for a Databricks DBI connection. Use oauth_db_token() for REST calls."
    )
  }
  host <- .odb_databricks_host(host)
  if (is.null(warehouse_id) && is.null(http_path)) {
    .odb_abort(
      "Supply warehouse_id or http_path for a Databricks DBI connection. Use oauth_db_token() for REST calls."
    )
  }
  if (!is.null(warehouse_id) && !is.null(http_path)) {
    .odb_abort("Supply only one of warehouse_id or http_path.")
  }
  .odb_string(warehouse_id, "warehouse_id", optional = TRUE)
  .odb_string(http_path, "http_path", optional = TRUE)
  options <- .odb_options(
    list(...),
    blocked = c(
      "host",
      "warehouse_id",
      "http_path",
      "drv",
      "token",
      "access_token",
      "token_provider",
      "auth_args",
      "authentication",
      "authenticator",
      "user",
      "password",
      "client_id",
      "client_secret"
    )
  )
  .odb_require("brickster", version = "0.2.14")
  # brickster stores a fixed bearer string, so rebuild when that token changes.
  .odb_bind(
    authorization,
    .odb_backend_databricks,
    host = host,
    warehouse_id = warehouse_id,
    http_path = http_path,
    options = options,
    target = target,
    required_scopes = required_scopes,
    cache_key = function(token) token(),
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_databricks <- function(
  token,
  host,
  warehouse_id,
  http_path,
  options
) {
  do.call(
    DBI::dbConnect,
    c(
      list(
        drv = brickster::DatabricksSQL(),
        host = host,
        warehouse_id = warehouse_id,
        http_path = http_path,
        token = token()
      ),
      options
    )
  )
}

#' Call Databricks functions as the signed-in user
#'
#' Use Databricks APIs with each visitor's account. Pass a brickster function
#' to the client's `$call()` method to list warehouses, run queries or perform
#' other supported operations. The client supplies the workspace and the
#' visitor's current token.
#'
#' @inheritParams oauth_db_databricks
#' @return A client object with `$call(.fn, ...)`. Pass a brickster function as
#'   `.fn` and its usual arguments through `...`, omitting `host` and
#'   `token`. The method returns the function's result.
#'   `$warehouses(timeout = 30)` lists visible SQL warehouses as a data frame
#'   with `id`, `name` and `state`, following all result pages. Listing doesn't
#'   start a warehouse or establish permission to run queries.
#' @details
#' Create the client inside `server()` and call its methods from render or
#' reactive expressions. Choose authentication settings when creating the
#' client; `$call()` supplies them to the brickster function.
#' Use [oauth_db_databricks()] for a DBI connection managed by shinyOAuthDB.
#' @section Longer operations:
#' Each brickster call gets a current token. Polling and fetching within
#' that call keep the supplied token. Operations don't retry automatically.
#' Your app must close any connections returned by brickster functions.
#' @examples
#' \dontrun{
#' databricks <- oauth_db_databricks_api(
#'   auth$connection,
#'   host = "example.cloud.databricks.com"
#' )
#' output$warehouses <- shiny::renderPrint({
#'   databricks$call(brickster::db_sql_warehouse_list)
#' })
#' }
#' @seealso [oauth_db_databricks()], [oauth_db_databricks_client()].
#'   `vignette("databricks", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_databricks_api <- function(
  authorization,
  host,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  host <- .odb_databricks_host(host)
  if (auth_mode == "entra") {
    required_scopes <- .odb_microsoft_scopes(required_scopes)
  }
  .odb_require("brickster", version = "0.2.14")
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_databricks_api$new(host, provider)
}

.odb_databricks_api <- R6::R6Class(
  "OAuthDatabricksAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(host, provider) {
      private$host <- host
      private$provider <- provider
    },
    warehouses = function(timeout = 30) {
      .odb_databricks_warehouses(private$provider(), private$host, timeout)
    },
    call = function(.fn, ...) {
      args <- .odb_api_arguments(
        .fn,
        list(...),
        blocked = c(
          "host",
          "token",
          "access_token",
          "token_provider",
          "auth_args",
          "authentication",
          "authenticator",
          "user",
          "password",
          "client_id",
          "client_secret"
        ),
        injected = c("host", "token")
      )
      provider <- private$provider()
      token <- provider()
      .odb_api_call(
        .fn,
        c(args, list(host = private$host, token = token)),
        check = function() provider(.check_only = TRUE),
        credentials = token
      )
    },
    print = function(...) {
      cat("<OAuthDatabricksAPI>\n")
      invisible(self)
    }
  ),
  private = list(host = NULL, provider = NULL)
)

.odb_databricks_warehouses <- function(token, host, timeout) {
  .odb_require("jsonlite")
  .odb_http_options(timeout, NULL)
  deadline <- .odb_http_time() + timeout
  page <- NULL
  seen <- character()
  rows <- list()
  scalar <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
  }
  repeat {
    req <- httr2::request(paste0("https://", host, "/api/2.0/sql/warehouses"))
    req <- httr2::req_url_query(req, page_size = 100L)
    if (!is.null(page)) {
      req <- httr2::req_url_query(req, page_token = page)
    }
    remaining <- deadline - .odb_http_time()
    if (remaining <= 0) {
      .odb_abort("Databricks warehouse listing timed out.", "timeout")
    }
    resp <- .odb_http_request(token, req, "Databricks", remaining)
    data <- .odb_http_json(resp, "Databricks")
    if (
      !is.list(data) || !is.null(data$warehouses) && !is.list(data$warehouses)
    ) {
      .odb_abort(
        "Databricks returned an invalid warehouse list.",
        "invalid_response"
      )
    }
    for (warehouse in data$warehouses) {
      if (
        !is.list(warehouse) ||
          !scalar(warehouse$id) ||
          !scalar(warehouse$name) ||
          !scalar(warehouse$state)
      ) {
        .odb_abort(
          "Databricks returned invalid warehouse details.",
          "invalid_response"
        )
      }
      rows[[length(rows) + 1L]] <- data.frame(
        id = warehouse$id,
        name = warehouse$name,
        state = warehouse$state,
        stringsAsFactors = FALSE
      )
    }
    page <- data$next_page_token
    if (is.null(page) || identical(page, "")) {
      break
    }
    if (!scalar(page) || page %in% seen || length(seen) >= 100L) {
      .odb_abort(
        "Databricks returned invalid warehouse pagination.",
        "invalid_response"
      )
    }
    seen <- c(seen, page)
  }
  token(.check_only = TRUE)
  if (!length(rows)) {
    return(data.frame(
      id = character(),
      name = character(),
      state = character()
    ))
  }
  result <- do.call(rbind, rows)
  result[!duplicated(result$id), , drop = FALSE]
}

#' Set up Databricks OAuth sign-in
#'
#' Set up sign-in for a Shiny app that uses a Databricks workspace. Pass
#' this client to shinyOAuth's UI and server modules, then query with
#' [oauth_db_databricks()] or [oauth_db_databricks_api()]. Each visitor uses
#' their own Databricks account and data permissions.
#'
#' @inheritParams oauth_db_microsoft_client
#' @param host Workspace hostname or HTTPS origin. Ignored when `provider`
#'   is supplied.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register your app and its exact redirect URI with Databricks. The defaults
#' request `all-apis` and refresh access; use `scopes` to replace them.
#' Omit `client_secret` for a public registration without a secret.
#'
#' For Azure Databricks using Microsoft Entra tokens, use
#' [oauth_db_microsoft_client()] with `services = "databricks_entra"`.
#' @examples
#' \dontrun{
#' client <- oauth_db_databricks_client(
#'   host = "example.cloud.databricks.com",
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_databricks_provider()].
#'   `vignette("databricks", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_databricks_client <- function(
  host,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  provider = .odb_databricks_provider(host, client_secret),
  scopes = c("openid", "profile", "email", "offline_access", "all-apis")
) {
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes = scopes,
    ...
  )
}

.odb_databricks_provider <- function(host, client_secret) {
  oauth_db_databricks_provider(
    host,
    token_auth_style = if (
      is.null(client_secret) ||
        !length(client_secret) ||
        identical(client_secret, "")
    ) {
      "public"
    } else {
      "header"
    }
  )
}

#' Create a Databricks OAuth provider
#'
#' Describe a Databricks workspace's sign-in service when building a custom
#' client with `shinyOAuth::oauth_client()`. The provider supplies the sign-in
#' and token endpoints. For the usual app setup, use
#' [oauth_db_databricks_client()] instead.
#'
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param token_auth_style `"header"` for a client with a secret, or
#'   `"public"` for an app registered without one.
#' @param ... Arguments for `shinyOAuth::oauth_provider_oidc_discover()`,
#'   replacing defaults.
#' @return A shinyOAuth `OAuthProvider`.
#' @details
#' The function discovers the workspace's sign-in endpoints over HTTPS.
#' Choose `token_auth_style` to match the app registration: `"header"` for
#' a client with a secret, or `"public"` for one registered without a secret.
#' @seealso [oauth_db_databricks_client()].
#'   `vignette("databricks", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_databricks_provider <- function(
  host,
  token_auth_style = c("header", "public"),
  ...
) {
  host <- .odb_databricks_host(host)
  defaults <- list(
    issuer = paste0("https://", host, "/oidc/.well-known/openid-configuration"),
    name = "databricks",
    token_auth_style = match.arg(token_auth_style),
    use_pkce = TRUE,
    use_nonce = TRUE,
    id_token_validation = TRUE,
    userinfo_required = FALSE
  )
  overrides <- list(...)
  .odb_named_args(overrides, "Provider settings in ...")
  defaults[names(overrides)] <- overrides
  do.call(shinyOAuth::oauth_provider_oidc_discover, defaults)
}

.odb_databricks_host <- function(host) {
  .odb_string(host, "host")
  host <- sub("/$", "", sub("^https://", "", host))
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9.-]*$", host)) {
    .odb_abort(
      "host must be a Databricks hostname or HTTPS origin without a path."
    )
  }
  tolower(host)
}

.odb_databricks_profiles <- function() {
  list(
    databricks_entra = .odb_microsoft_profile(
      "databricks",
      "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d",
      "user_impersonation"
    )
  )
}
