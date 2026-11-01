#' Query Snowflake as the signed-in user
#'
#' Use a Snowflake OAuth authorization with DBI or dbplyr. Supply a role the user
#' can access and, optionally, the warehouse, database, and schema for queries.
#'
#' @inheritParams oauth_db_azure_sql
#' @param database,schema,warehouse Optional connection settings. `NULL` uses the
#'   driver's or account's defaults.
#' @param role Snowflake role for this connection.
#' @param required_scopes OAuth permissions to check. Defaults to the native
#'   Snowflake role scope, `paste0("session:role:", role)`. For External OAuth,
#'   supply the scopes configured by your integration.
#' @param target Optional shinyOAuth token target, for example for External OAuth.
#' @param ... Additional named Snowflake ODBC connection options.
#' @return A reactive function returning an odbc DBI connection.
#' @details
#' Install odbc and the Snowflake ODBC driver. Use [oauth_db_snowflake_client()]
#' for native Snowflake OAuth, or keep your existing External OAuth client.
#'
#' Create the helper in `server()` and call `con()` for each operation.
#' Connections open on first use and close on sign-out or session end.
#' For names containing ODBC delimiters, use [odbc::quote_value()].
#' @examples
#' \dontrun{
#' con <- oauth_db_snowflake(
#'   auth$connection,
#'   server = "organization-account.snowflakecomputing.com",
#'   role = "REPORTING_READER",
#'   warehouse = "REPORTING_WH",
#'   database = "ANALYTICS"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER(), CURRENT_ROLE()")
#' })
#' }
#' @seealso [oauth_db_snowflake_client()]
#' @family database connections
#' @export
oauth_db_snowflake <- function(
  authorization, server, database = NULL, schema = NULL, warehouse = NULL, role, ...,
  required_scopes = paste0("session:role:", role),
  target = NULL, driver = "SnowflakeDSIIDriver", min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
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
    driver = driver, options = options, target = target, required_scopes = required_scopes,
    min_valid_for = min_valid_for, session = session)
}

.odb_backend_snowflake <- function(token, server, database, schema, warehouse, role, driver, options) {
  context <- list(database = database, schema = schema, warehouse = warehouse)
  context <- context[!vapply(context, is.null, logical(1))]
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver, server = server,
    role = role, authenticator = "oauth", token = token()), context, options))
}

#' Set up Snowflake OAuth sign-in
#'
#' Create sign-in settings for Snowflake's own OAuth integration. Use this
#' before [oauth_db_snowflake()] when your app needs a particular Snowflake role.
#'
#' @inheritParams oauth_db_microsoft_client
#' @param server Snowflake account hostname. Not used when `provider` is supplied.
#' @param client_secret Client secret from the Snowflake OAuth integration.
#' @param role Requested database role. Not used when `scopes` is supplied.
#' @return A shinyOAuth `OAuthClient` for its UI and server modules.
#' @details
#' Create the client outside `server()`. For External OAuth through Entra or
#' another identity provider, use that provider's shinyOAuth configuration.
#' @examples
#' \dontrun{
#' client <- oauth_db_snowflake_client(
#'   server = "organization-account.snowflakecomputing.com",
#'   role = "REPORTING_READER",
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_snowflake_provider()]
#' @family sign-in configuration
#' @export
oauth_db_snowflake_client <- function(
  server, client_id, client_secret, redirect_uri, role, ...,
  provider = oauth_db_snowflake_provider(server),
  scopes = c(paste0("session:role:", role), "refresh_token")
) {
  if (missing(scopes)) .odb_string(role, "role")
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret, scopes = scopes, ...)
}

#' Set up a Snowflake OAuth provider
#'
#' Use this when constructing your own `shinyOAuth::oauth_client()` for
#' Snowflake's built-in OAuth integration. For standard setup, use
#' [oauth_db_snowflake_client()].
#'
#' @param server Snowflake account hostname.
#' @param ... Settings for `shinyOAuth::oauth_provider()`, replacing preset values.
#' @return A shinyOAuth `OAuthProvider`. External OAuth uses the external
#'   identity provider's configuration instead.
#' @family sign-in configuration
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
  .odb_named_args(overrides, "Provider settings in ...")
  defaults[names(overrides)] <- overrides
  do.call(shinyOAuth::oauth_provider, defaults)
}
