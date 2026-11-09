#' Query Redshift as the signed-in user
#'
#' Read Redshift data in a Shiny app using each visitor's database
#' permissions. The helper opens a DBI connection through Redshift's
#' IAM Identity Center integration for SQL or dbplyr queries.
#'
#' @inheritParams oauth_db_azure_sql
#' @param token_type `"EXT_JWT"` for an external provider's JWT access token,
#'   or `"ACCESS_TOKEN"` for an IAM Identity Center access token.
#' @param ... Named Redshift ODBC options, such as `CaFile` or `LoginTimeout`.
#'   The helper sets authentication and verified TLS.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and the Redshift ODBC 2.x driver with `IdpTokenAuthPlugin`.
#' Configure IAM Identity Center to trust your sign-in provider and map users
#' to database permissions. Your shinyOAuth client must obtain a token for
#' the audience accepted by that integration.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' @section Connection lifetime:
#' Connections open on first use and close after sign-out, account changes
#' or session end. An established SQL connection stays open through ordinary
#' token renewal; a new connection gets a current token.
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
#' @export
oauth_db_redshift <- function(
  authorization,
  server,
  database,
  ...,
  driver = "Amazon Redshift (x64)",
  port = 5439L,
  token_type = c("EXT_JWT", "ACCESS_TOKEN"),
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  .odb_string(database, "database")
  .odb_string(driver, "driver")
  token_type <- match.arg(token_type)
  if (
    length(port) != 1L ||
      is.na(port) ||
      !grepl("^[0-9]+$", port) ||
      as.numeric(port) < 1 ||
      as.numeric(port) > 65535
  ) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  options <- .odb_options(
    list(...),
    blocked = c(
      "server",
      "host",
      "hostname",
      "database",
      "port",
      "portnumber",
      "driver",
      "drv",
      "dsn",
      "filedsn",
      "savefile",
      ".connection_string",
      "connection_string",
      "attributes",
      "plugin_name",
      "token",
      "token_type",
      "access_token",
      "web_identity_token",
      "user",
      "uid",
      "logonid",
      "dbuser",
      "pwd",
      "password",
      "authentication",
      "authtype",
      "iam",
      "profile",
      "authprofile",
      "instanceprofile",
      "accesskeyid",
      "secretaccesskey",
      "sessiontoken",
      "client_id",
      "client_secret",
      "idp_host",
      "idp_port",
      "idp_tenant",
      "issuer_url",
      "login_url",
      "provider_name",
      "endpointurl",
      "stsendpointurl",
      "sslmode",
      "ssl_insecure",
      "min_tls",
      "encrypt",
      "trust_server_certificate"
    ),
    partial = "dsn"
  )
  .odb_odbc_values(c(list(server, database, driver), options))
  .odb_bind(
    authorization,
    .odb_backend_redshift,
    server = server,
    database = database,
    driver = driver,
    port = as.integer(port),
    token_type = token_type,
    options = options,
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_redshift <- function(
  token,
  server,
  database,
  driver,
  port,
  token_type,
  options
) {
  .odb_odbc_connect(
    c(
      list(
        drv = odbc::odbc(),
        driver = driver,
        server = server,
        port = port,
        database = database,
        plugin_name = "IdpTokenAuthPlugin",
        token = token(),
        token_type = token_type,
        SSLMode = "verify-full",
        ssl_insecure = 0L
      ),
      options
    )
  )
}
