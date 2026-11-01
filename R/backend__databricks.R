#' Query Databricks SQL as the signed-in user
#'
#' Use this for SQL queries with DBI or dbplyr through brickster. Supply a SQL
#' warehouse and the user's Databricks OAuth or Entra authorization.
#'
#' @inheritParams oauth_db_connect
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param warehouse_id SQL warehouse ID. Supply this or `http_path`.
#' @param http_path Warehouse HTTP path, such as
#'   `"/sql/1.0/warehouses/warehouse-id"`. Supply this or `warehouse_id`.
#' @param ... Connection options for brickster, such as `catalog` and `schema`.
#' @param auth_mode `"databricks_oauth"`, or `"entra"` for Azure Databricks
#'   using a Microsoft authorization.
#' @param target Token target name. Defaults to `"databricks"` for Entra;
#'   native Databricks OAuth uses the authorization's default token.
#' @return A reactive function returning a brickster DBI connection.
#' @details
#' Install brickster. Create `con` in `server()` and call it for each operation;
#' the helper replaces brickster's connection when its stored token changes.
#' A saved handle keeps its own token, even after local sign-out.
#'
#' For workspace APIs and other brickster functions, use
#' [oauth_db_databricks_api()].
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
#' @seealso [oauth_db_databricks_client()]
#' @family database connections
#' @export
oauth_db_databricks <- function(
  authorization, host, warehouse_id = NULL, ..., http_path = NULL,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  required_scopes = character(), min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  if (auth_mode == "entra") required_scopes <- .odb_microsoft_scopes(required_scopes)
  if (missing(host)) .odb_abort("Supply host for a Databricks DBI connection. Use oauth_db_token() for REST calls.")
  host <- .odb_databricks_host(host)
  if (is.null(warehouse_id) && is.null(http_path)) {
    .odb_abort("Supply warehouse_id or http_path for a Databricks DBI connection. Use oauth_db_token() for REST calls.")
  }
  if (!is.null(warehouse_id) && !is.null(http_path)) {
    .odb_abort("Supply only one of warehouse_id or http_path.")
  }
  .odb_string(warehouse_id, "warehouse_id", optional = TRUE)
  .odb_string(http_path, "http_path", optional = TRUE)
  options <- .odb_options(list(...), blocked = c(
    "host", "warehouse_id", "http_path", "drv", "token", "access_token",
    "token_provider", "auth_args", "authentication", "authenticator", "user",
    "password", "client_id", "client_secret"))
  .odb_require("brickster", version = "0.2.14")
  # brickster stores a fixed bearer string, so rebuild when that token changes.
  .odb_bind(authorization, .odb_backend_databricks, host = host,
    warehouse_id = warehouse_id, http_path = http_path, options = options, target = target,
    required_scopes = required_scopes, cache_key = function(token) token(),
    min_valid_for = min_valid_for, session = session)
}

.odb_backend_databricks <- function(token, host, warehouse_id, http_path, options) {
  do.call(DBI::dbConnect, c(list(drv = brickster::DatabricksSQL(), host = host,
    warehouse_id = warehouse_id, http_path = http_path, token = token()), options))
}

#' Call Databricks functions as the signed-in user
#'
#' Use brickster functions to list warehouses, run SQL, or work with other
#' Databricks APIs. The client supplies the workspace host and a current user
#' token when you call `$call()`.
#'
#' @inheritParams oauth_db_databricks
#' @return An R6 client with `$call(.fn, ...)`. Pass a brickster function as
#'   `.fn` and its usual arguments through `...`, omitting `host` and `token`.
#'   The method returns the function's result.
#' @details
#' Create the client inside `server()`. Configure authentication on this client;
#' authentication arguments cannot be overridden through `$call()`.
#'
#' Each call obtains a current token. A long-running native operation retains
#' that token during polling or fetching. The client doesn't retry operations
#' or close connections returned by an upstream function.
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
#' @seealso [oauth_db_databricks()], [oauth_db_databricks_client()]
#' @family platform API clients
#' @export
oauth_db_databricks_api <- function(
  authorization, host, auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  required_scopes = character(), min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  host <- .odb_databricks_host(host)
  if (auth_mode == "entra") required_scopes <- .odb_microsoft_scopes(required_scopes)
  .odb_require("brickster", version = "0.2.14")
  bearer <- oauth_db_token(authorization, target = target,
    required_scopes = required_scopes, min_valid_for = min_valid_for, session = session)
  .odb_databricks_api$new(bearer, host)
}

.odb_databricks_api <- R6::R6Class("OAuthDatabricksAPI", cloneable = FALSE,
  public = list(
    initialize = function(bearer, host) {
      private$bearer <- bearer
      private$host <- host
    },
    call = function(.fn, ...) {
      args <- .odb_api_arguments(.fn, list(...), blocked = c(
        "host", "token", "access_token", "token_provider", "auth_args",
        "authentication", "authenticator", "user", "password", "client_id", "client_secret"),
        injected = c("host", "token"))
      token <- private$bearer()
      do.call(.fn, c(args, list(host = private$host, token = token)))
    },
    print = function(...) {
      cat("<OAuthDatabricksAPI>\n")
      invisible(self)
    }
  ),
  private = list(bearer = NULL, host = NULL)
)

#' Set up Databricks OAuth sign-in
#'
#' Create sign-in settings for a Databricks workspace. Pass this client to
#' shinyOAuth's UI and server modules, then use the resulting authorization
#' with the SQL or API helper.
#'
#' @inheritParams oauth_db_microsoft_client
#' @param host Workspace hostname or HTTPS origin. Not used when `provider`
#'   is supplied.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register the app and redirect URI with Databricks first. The default scopes
#' include `all-apis` and refresh access; you can supply a different scope list.
#'
#' For Azure Databricks using Entra tokens, use [oauth_db_microsoft_client()]
#' with `services = "databricks_entra"` instead.
#' @examples
#' \dontrun{
#' client <- oauth_db_databricks_client(
#'   host = "example.cloud.databricks.com",
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_databricks_provider()]
#' @family sign-in configuration
#' @export
oauth_db_databricks_client <- function(
  host, client_id, redirect_uri, client_secret = NULL, ...,
  provider = .odb_databricks_provider(host, client_secret),
  scopes = c("openid", "profile", "email", "offline_access", "all-apis")
) {
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret,
    scopes = scopes, ...)
}

.odb_databricks_provider <- function(host, client_secret) {
  oauth_db_databricks_provider(host,
    token_auth_style = if (is.null(client_secret) || !length(client_secret) ||
      identical(client_secret, "")) "public" else "header")
}

#' Set up a Databricks OAuth provider
#'
#' Use this when constructing your own `shinyOAuth::oauth_client()`. It
#' discovers sign-in endpoints from the workspace. For standard setup, use
#' [oauth_db_databricks_client()].
#'
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param token_auth_style `"header"` for a client with a secret, or `"public"`
#'   for an app registered without one.
#' @param ... Settings for `shinyOAuth::oauth_provider_oidc_discover()`,
#'   replacing preset values.
#' @return A shinyOAuth `OAuthProvider`. Construction makes an HTTPS
#'   discovery request.
#' @family sign-in configuration
#' @export
oauth_db_databricks_provider <- function(host, token_auth_style = c("header", "public"), ...) {
  host <- .odb_databricks_host(host)
  defaults <- list(issuer = paste0("https://", host, "/oidc/.well-known/openid-configuration"),
    name = "databricks", token_auth_style = match.arg(token_auth_style),
    use_pkce = TRUE, use_nonce = TRUE, id_token_validation = TRUE, userinfo_required = FALSE)
  overrides <- list(...)
  .odb_named_args(overrides, "Provider settings in ...")
  defaults[names(overrides)] <- overrides
  do.call(shinyOAuth::oauth_provider_oidc_discover, defaults)
}

.odb_databricks_host <- function(host) {
  .odb_string(host, "host")
  host <- sub("/$", "", sub("^https://", "", host))
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9.-]*$", host)) {
    .odb_abort("host must be a Databricks hostname or HTTPS origin without a path.")
  }
  tolower(host)
}

.odb_databricks_profiles <- function() {
  list(databricks_entra = .odb_microsoft_profile(
    "databricks", "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d", "user_impersonation"))
}
