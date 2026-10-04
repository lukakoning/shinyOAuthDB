#' Use the user's authorization with Snowflake
#'
#' Configure the OAuth client in shinyOAuth to match the account's native or
#' external OAuth integration. Native Snowflake OAuth derives its scope from
#' `role`; supply explicit `scopes` for an external or customized integration.
#' The ODBC driver receives `authenticator = "oauth"` and the user's access token.
#' @inheritParams oauth_db_azure_sql
#' @param schema,warehouse,role Explicit Snowflake connection context.
#' @param scopes Scopes configured by the account's OAuth integration. Defaults
#'   to `paste0("session:role:", role)` for native Snowflake OAuth.
#' @param target Optional named shinyOAuth token target for external OAuth.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_snowflake <- function(
  authorization, server, database, schema, warehouse, role, ...,
  scopes = paste0("session:role:", role),
  target = NULL, driver = "SnowflakeDSIIDriver", min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc")
  .odb_string(role, "role")
  .odb_odbc_values(list(server, database, schema, warehouse, role, driver))
  options <- .odb_options(list(...), blocked = c(
    "server", "database", "schema", "warehouse", "role", "driver", "drv", "dsn",
    ".connection_string", "connection_string", "attributes", "user", "uid", "pwd",
    "password", "token", "access_token", "authentication", "authenticator",
    "token_file_path", "client_secret", "oauth_client_id", "oauth_client_secret",
    "oauth_scope", "insecure_mode", "disable_saml_url_check", "encrypt",
    "trust_server_certificate"))
  .odb_odbc_values(options)
  .odb_bind(authorization, .odb_backend_snowflake, server = server,
    database = database, schema = schema, warehouse = warehouse, role = role,
    driver = driver, options = options, target = target, scopes = scopes,
    min_valid_for = min_valid_for, session = session)
}

.odb_backend_snowflake <- function(token, server, database, schema, warehouse, role, driver, options) {
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver, server = server,
    database = database, schema = schema, warehouse = warehouse, role = role,
    authenticator = "oauth", token = token()), options))
}

#' Configure a native Snowflake shinyOAuth client
#' @param server Snowflake account hostname. Unused when `provider` is supplied.
#' @param role Requested database role. Unused when `scopes` is supplied.
#' @inheritParams oauth_db_microsoft_client
#' @return A native shinyOAuth client. External OAuth instead uses its configured
#'   identity provider through shinyOAuth directly.
#' @export
oauth_db_snowflake_client <- function(
  server, client_id, client_secret, redirect_uri, role, ...,
  provider = oauth_db_snowflake_provider(server),
  scopes = c(paste0("session:role:", role), "refresh_token")
) {
  if (missing(scopes)) .odb_string(role, "role")
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret, scopes = scopes, ...)
}

#' Configure a native Snowflake shinyOAuth provider
#'
#' A provider preset for Snowflake's built-in OAuth integration. Pass it to
#' `shinyOAuth::oauth_client()` with your registered credentials and scopes.
#' External OAuth uses the external identity provider's configuration instead.
#' @param server Snowflake account hostname.
#' @param ... Named `shinyOAuth::oauth_provider()` settings. Explicit values
#'   replace the preset defaults, including endpoints and client authentication.
#' @return An ordinary shinyOAuth provider, independent of the database bridge.
#' @export
oauth_db_snowflake_provider <- function(server, ...) {
  .odb_string(server, "server")
  if (!grepl("^[A-Za-z0-9.-]+$", server)) .odb_abort("server must be a Snowflake hostname.")
  base <- paste0("https://", server)
  defaults <- list(name = "snowflake",
    auth_url = paste0(base, "/oauth/authorize"), token_url = paste0(base, "/oauth/token-request"),
    userinfo_required = FALSE, id_token_required = FALSE, id_token_validation = FALSE,
    use_nonce = FALSE, use_pkce = TRUE, token_auth_style = "header")
  overrides <- list(...)
  if (length(overrides) && (is.null(names(overrides)) || anyNA(names(overrides)) ||
      any(!nzchar(names(overrides))) || anyDuplicated(names(overrides)))) {
    .odb_abort("Provider settings in ... must have unique names.")
  }
  defaults[names(overrides)] <- overrides
  do.call(shinyOAuth::oauth_provider, defaults)
}
