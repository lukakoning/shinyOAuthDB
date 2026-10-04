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
#' token <- oauth_db_databricks(auth$connection)
#' output$result <- shiny::renderPrint({
#'   brickster::db_sql_query(host = "example.cloud.databricks.com",
#'     warehouse_id = "warehouse-id", statement = "SELECT current_user()",
#'     token = token())
#' })
#' }
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
    scopes <- if (auth_mode == "entra") .odb_databricks_profiles()$databricks_entra$scopes else "all-apis"
  }
  if (auth_mode == "entra") scopes <- .odb_microsoft_scopes(scopes)
  if (!is.null(host)) host <- .odb_databricks_host(host)
  options <- .odb_options(list(...), blocked = c(
    "host", "warehouse_id", "http_path", "drv", "token", "access_token",
    "token_provider", "auth_args", "authentication", "authenticator", "user",
    "password", "client_id", "client_secret"))
  if (is.null(warehouse_id) && length(options)) {
    .odb_abort("Connection options in ... require a warehouse_id; pass REST options to the native call.")
  }
  if (is.null(warehouse_id)) {
    return(oauth_db_token(authorization, target = target, scopes = scopes,
      min_valid_for = min_valid_for, session = session))
  }
  if (is.null(host)) .odb_abort("Supply host when warehouse_id requests a Databricks DBI connection.")
  .odb_require("brickster")
  # brickster stores a fixed bearer string, so rebuild when that token changes.
  .odb_bind(authorization, .odb_backend_databricks, host = host,
    warehouse_id = warehouse_id, options = options, target = target,
    scopes = scopes, cache_key = function(token) token(),
    min_valid_for = min_valid_for, session = session)
}

.odb_backend_databricks <- function(token, host, warehouse_id, options) {
  do.call(DBI::dbConnect, c(list(drv = brickster::DatabricksSQL(), host = host,
    warehouse_id = warehouse_id, token = token()), options))
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
