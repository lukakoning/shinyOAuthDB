#' Use the user's authorization with Databricks
#'
#' Returns a native brickster DBI connection. Supply either `warehouse_id` or
#' `http_path`, as with brickster's `DBI::dbConnect()` method. For REST functions,
#' use [oauth_db_token()] to supply their `token` argument instead.
#' Call the accessor for each operation. Its native DBI connection holds a fixed
#' token, so the accessor replaces it when shinyOAuth refreshes the credential.
#' A previously returned connection is a snapshot; do not retain it
#' across operations or authorizations. Endpoints belong in app configuration.
#' @inheritParams oauth_db_connect
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param warehouse_id SQL warehouse ID. Supply this or `http_path`.
#' @param http_path Native SQL warehouse HTTP path, such as
#'   `/sql/1.0/warehouses/warehouse-id`. Supply this or `warehouse_id`.
#' @param ... Native `DBI::dbConnect()` options, such as `catalog` and `schema`.
#' @param auth_mode `"databricks_oauth"` or `"entra"` for Azure Databricks.
#' @param target Declared token target. Defaults to `"databricks"` for Entra;
#'   native Databricks OAuth uses the main authorization.
#' @param scopes Delegated scopes, or `NULL` for the chosen authentication mode.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @seealso [oauth_db_databricks_client()], [oauth_db_databricks_provider()]
#' @examples
#' \dontrun{
#' # Inside server(), after creating auth with shinyOAuth:
#' con <- oauth_db_databricks(auth$connection,
#'   host = "example.cloud.databricks.com", warehouse_id = "warehouse-id")
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user() AS database_user")
#' })
#'
#' # Or use brickster's API directly with a current bearer string:
#' token <- oauth_db_token(auth$connection, scopes = "all-apis")
#' output$result <- shiny::renderPrint({
#'   brickster::db_sql_query(host = "example.cloud.databricks.com",
#'     warehouse_id = "warehouse-id", statement = "SELECT current_user()",
#'     token = token())
#' })
#' }
#' @export
oauth_db_databricks <- function(
  authorization, host, warehouse_id = NULL, ..., http_path = NULL,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  scopes = NULL, min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  auth_mode <- match.arg(auth_mode)
  if (is.null(scopes)) {
    scopes <- if (auth_mode == "entra") .odb_databricks_profiles()$databricks_entra$scopes else "all-apis"
  }
  if (auth_mode == "entra") scopes <- .odb_microsoft_scopes(scopes)
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
  .odb_require("brickster")
  # brickster stores a fixed bearer string, so rebuild when that token changes.
  .odb_bind(authorization, .odb_backend_databricks, host = host,
    warehouse_id = warehouse_id, http_path = http_path, options = options, target = target,
    scopes = scopes, cache_key = function(token) token(),
    min_valid_for = min_valid_for, session = session)
}

.odb_backend_databricks <- function(token, host, warehouse_id, http_path, options) {
  do.call(DBI::dbConnect, c(list(drv = brickster::DatabricksSQL(), host = host,
    warehouse_id = warehouse_id, http_path = http_path, token = token()), options))
}

#' Configure a native Databricks shinyOAuth client
#' @param host Databricks workspace hostname or HTTPS origin. Unused when
#'   `provider` is supplied.
#' @inheritParams oauth_db_microsoft_client
#' @return A native shinyOAuth client. Default provider discovery makes an HTTPS
#'   request to the workspace; supplying `provider` bypasses discovery.
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

#' Configure a native Databricks shinyOAuth provider
#'
#' Discovers the workspace's OpenID Connect endpoints using shinyOAuth.
#' Independent of brickster; pass the result to `shinyOAuth::oauth_client()`.
#' @param host Databricks workspace hostname or HTTPS origin.
#' @param token_auth_style `"header"` for a confidential client, or `"public"`
#'   for an application registered without a secret.
#' @param ... Named settings passed to `shinyOAuth::oauth_provider_oidc_discover()`.
#'   Explicit settings replace the preset defaults.
#' @return A native shinyOAuth provider. Discovery makes an HTTPS request.
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
