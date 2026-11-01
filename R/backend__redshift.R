#' Query Redshift as the signed-in user
#'
#' Use DBI or dbplyr with a user token accepted by Redshift's IAM Identity
#' Center integration. Keep your shinyOAuth client configured for that
#' deployment's identity provider and token audience.
#'
#' @inheritParams oauth_db_azure_sql
#' @param token_type "EXT_JWT" for an external IdP's JWT access token, or "ACCESS_TOKEN"
#'   for an IAM Identity Center access token.
#' @param ... Additional named Redshift ODBC options, such as CaFile or
#'   LoginTimeout. Authentication, profiles, and TLS settings are supplied
#'   by the helper.
#' @return A reactive function returning a DBI connection.
#' @details
#' Install odbc and the AWS Redshift ODBC 2.x driver with IdpTokenAuthPlugin
#' support. The AWS deployment must trust the issuer and map the user's
#' identity and permissions. A successful web sign-in alone is insufficient.
#'
#' This uses plain odbc::odbc() with an explicit token and token type.
#' It does not discover IAM credentials or open the driver's browser login.
#' Connections use verified TLS, open on first use, and close on authorization
#' changes or session end. Established SQL sessions remain open during ordinary
#' token refresh; a new connection obtains a current token.
#'
#' Identity-enhanced IAM credentials and SUBJECT_TOKEN are separate
#' authentication paths and are not accepted by this helper.
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
