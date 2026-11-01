#' Query Redshift as the signed-in user
#'
#' Query Redshift with a visitor's own access using DBI or dbplyr.
#' This helper connects through Redshift's IAM Identity Center integration.
#'
#' @inheritParams oauth_db_azure_sql
#' @param token_type `"EXT_JWT"` for an external provider's JWT access token,
#'   or `"ACCESS_TOKEN"` for an IAM Identity Center access token.
#' @param ... Named Redshift ODBC options, such as `CaFile` or `LoginTimeout`.
#'   The helper sets authentication and verified TLS.
#' @return A reactive function returning an odbc DBI connection.
#' @details
#' Install odbc and the AWS Redshift ODBC 2.x driver with
#' `IdpTokenAuthPlugin` support. The deployment must trust your app's sign-in
#' provider and map users to database permissions. Configure a shinyOAuth
#' client for that provider and the required token audience.
#'
#' Create `con` inside `server()` and call it before querying in a render
#' or reactive expression.
#' @section Connection lifetime:
#' Connections open on first use and close on authorization changes,
#' sign-out, or session end. Ordinary token refresh preserves an established
#' SQL connection; a new connection obtains a current token.
#' @section Authentication options:
#' The helper passes the token to the driver's `IdpTokenAuthPlugin`.
#' Use one of the two `token_type` values above. Identity-enhanced IAM
#' credentials and `SUBJECT_TOKEN` use separate authentication flows.
#' @examples
#' \dontrun{
#' con <- oauth_db_redshift(
#'   auth$connection,
#'   server = "cluster.example.eu-west-1.redshift.amazonaws.com",
#'   database = "reporting",
#'   token_type = "EXT_JWT"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user")
#' })
#' }
#' @seealso [oauth_db_microsoft_client()].
#'   `vignette("redshift", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family database connections
#' @export
oauth_db_redshift <- function(
  authorization, server, database, ...,
  driver = "Amazon Redshift (x64)", port = 5439L,
  token_type = c("EXT_JWT", "ACCESS_TOKEN"), target = NULL,
  required_scopes = character(), min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  .odb_string(database, "database")
  .odb_string(driver, "driver")
  token_type <- match.arg(token_type)
  if (length(port) != 1L || is.na(port) || !grepl("^[0-9]+$", port) ||
      as.numeric(port) < 1 || as.numeric(port) > 65535) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  options <- .odb_options(list(...), blocked = c(
    "server", "host", "hostname", "database", "port", "portnumber", "driver", "drv",
    "dsn", "filedsn", "savefile", ".connection_string", "connection_string", "attributes",
    "plugin_name", "token", "token_type", "access_token", "web_identity_token",
    "user", "uid", "logonid", "dbuser", "pwd", "password", "authentication", "authtype",
    "iam", "profile", "authprofile", "instanceprofile", "accesskeyid", "secretaccesskey",
    "sessiontoken", "client_id", "client_secret", "idp_host", "idp_port", "idp_tenant",
    "issuer_url", "login_url", "provider_name", "endpointurl", "stsendpointurl",
    "sslmode", "ssl_insecure", "min_tls", "encrypt", "trust_server_certificate"
  ))
  .odb_odbc_values(c(list(server, database, driver), options))
  .odb_bind(authorization, .odb_backend_redshift, server = server, database = database,
    driver = driver, port = as.integer(port), token_type = token_type, options = options,
    target = target, required_scopes = required_scopes, min_valid_for = min_valid_for, session = session)
}

.odb_backend_redshift <- function(token, server, database, driver, port, token_type, options) {
  do.call(DBI::dbConnect, c(list(
    drv = odbc::odbc(), driver = driver, server = server, port = port,
    database = database, plugin_name = "IdpTokenAuthPlugin",
    token = token(), token_type = token_type,
    SSLMode = "verify-full", ssl_insecure = 0L
  ), options))
}
