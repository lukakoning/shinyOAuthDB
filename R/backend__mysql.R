#' Query Azure MySQL as the signed-in user
#'
#' Read Azure Database for MySQL Flexible Server data with each visitor's
#' Microsoft account and database permissions. The helper opens a MariaDB
#' Connector/ODBC connection for DBI or dbplyr queries.
#'
#' @inheritParams oauth_db_connect
#' @param server One MySQL server hostname, usually ending in
#'   `.mysql.database.azure.com`.
#' @param database Default database name.
#' @param user Entra user or group name created in MySQL, or a reactive
#'   function returning that name. The server checks the identity mapping.
#' @param driver Registered MariaDB Connector/ODBC driver name. Some driver
#'   managers also accept a library path.
#'   Use MariaDB Connector/ODBC 3.1 or later. MySQL Connector/ODBC uses
#'   different options and is not supported by this helper.
#' @param port TCP port, default `3306`.
#' @param ssl_ca PEM CA certificate bundle path, or `NULL` to use the driver's
#'   trust configuration. Supply the bundle recommended for your Azure server.
#' @param ... Result and timeout options: `timeout`, `timezone`, `timezone_out`,
#'   `bigint`, `encoding`, `name_encoding`, `interruptible`, or `FORWARDONLY`.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and MariaDB Connector/ODBC. Configure Azure MySQL for Entra
#' authentication and create users or groups with the required database
#' privileges. Use [oauth_db_microsoft_client()] with `services = "mysql"`.
#'
#' The helper sends the visitor's access token as the password through
#' `mysql_clear_password`, with TLS certificate and hostname verification.
#' MariaDB's client library supplies the cleartext plugin without a global
#' environment setting. DSNs, option files, alternate credentials and
#' automatic reconnection are disabled.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' The next access replaces the connection when its token or username
#' changes. Ordinary token renewal does not rerun completed reactive queries.
#' Sign-out, account changes and session end close the connection.
#' If a query reports a broken connection, disconnect that native handle and
#' call `con()` again. Failed queries are never replayed automatically.
#' @examples
#' \dontrun{
#' con <- oauth_db_azure_mysql(
#'   auth$connection,
#'   server = "example.mysql.database.azure.com",
#'   database = "reporting",
#'   user = "reporting-readers",
#'   driver = "MariaDB ODBC 3.2 Driver",
#'   ssl_ca = "path/to/azure-ca.pem"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER() AS database_user")
#' })
#' }
#' @seealso [oauth_db_microsoft_client()].
#'   `vignette("azure-mysql", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_azure_mysql <- function(
  authorization,
  server,
  database,
  user,
  driver,
  ...,
  port = 3306L,
  ssl_ca = NULL,
  target = "mysql",
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  .odb_string(database, "database")
  .odb_string(driver, "driver")
  if (grepl("mysql|myodbc", basename(driver), ignore.case = TRUE)) {
    .odb_abort(
      "Use MariaDB Connector/ODBC for Azure MySQL; MySQL Connector/ODBC is not supported."
    )
  }
  .odb_string(ssl_ca, "ssl_ca", optional = TRUE)
  .odb_odbc_values(list(server, database, driver, ssl_ca))
  if (grepl("[,/\\\\[:space:]]", server)) {
    .odb_abort("server must be one TCP hostname or address.")
  }
  if (
    !typeof(port) %in% c("integer", "double") ||
      length(port) != 1L ||
      is.na(port) ||
      !is.finite(port) ||
      port < 1 ||
      port > 65535 ||
      port != floor(port)
  ) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  if (!is.function(user)) {
    .odb_string(user, "user")
    .odb_odbc_values(list(user))
  }
  username <- function() {
    value <- if (is.function(user)) user() else user
    .odb_string(value, "user")
    .odb_odbc_values(list(value))
    value
  }
  options <- list(...)
  .odb_named_args(options, "Azure MySQL options")
  allowed <- c(
    "timeout",
    "timezone",
    "timezone_out",
    "bigint",
    "encoding",
    "name_encoding",
    "interruptible",
    "FORWARDONLY"
  )
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(
      "Only the documented result and timeout options are accepted in ...; authentication, routing, reconnect and TLS settings cannot be overridden."
    )
  }
  .odb_odbc_values(options)
  .odb_bind(
    authorization,
    .odb_backend_azure_mysql,
    server = server,
    database = database,
    user = username,
    driver = driver,
    port = as.integer(port),
    ssl_ca = ssl_ca,
    options = options,
    identity_key = username,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_azure_mysql <- function(
  token,
  server,
  database,
  user,
  driver,
  port,
  ssl_ca,
  options
) {
  args <- list(
    drv = odbc::odbc(),
    driver = driver,
    SERVER = server,
    DATABASE = database,
    UID = user(),
    PWD = token(),
    PORT = port,
    FORCETLS = 1L,
    SSLVERIFY = 1L,
    TCPIP = 1L,
    USE_MYCNF = 0L,
    NO_PROMPT = 1L,
    AUTO_RECONNECT = 0L
  )
  if (!is.null(ssl_ca)) {
    args$SSLCA <- ssl_ca
  }
  .odb_odbc_connect(c(args, options))
}

.odb_mysql_profiles <- function(explicit_scopes = FALSE) {
  list(
    mysql = .odb_microsoft_profile(
      "mysql",
      "https://ossrdbms-aad.database.windows.net",
      if (explicit_scopes) "user_impersonation" else ".default"
    )
  )
}
