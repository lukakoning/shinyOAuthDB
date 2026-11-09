#' Query SingleStore as the signed-in user
#'
#' Query SingleStore or SingleStore Helios using each visitor's database
#' privileges. The helper supplies their JWT access token to SingleStore's
#' ODBC driver and returns a DBI connection for SQL or dbplyr queries.
#'
#' @inheritParams oauth_db_connect
#' @param server One SingleStore SQL endpoint hostname or IPv4 address,
#'   without a protocol or port.
#' @param database Optional default database. `NULL` uses the server default.
#' @param ssl_ca Path to a PEM file containing the trusted server CA chain.
#'   Required to enforce encrypted connections with the SingleStore driver.
#' @param user SingleStore username, or a reactive function returning it.
#'   The default `"*"` lets SingleStore select the user from its trusted JWT
#'   mapping; this requires SingleStore 8.1.20 or later.
#' @param driver Installed SingleStore ODBC driver name or library path.
#'   Use SingleStore Connector/ODBC 1.2.1 or later.
#' @param port SQL endpoint port, default `3306`.
#' @param ... Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
#'   `encoding`, `name_encoding`, `interruptible`, `NO_CACHE`, `FORWARDONLY`,
#'   and `COMPAT_MODE`. Authentication, routing, reconnect and TLS settings
#'   cannot be overridden.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and SingleStore's ODBC driver. Configure the database to
#' trust your provider's JWT access tokens and map them to users created
#' with `authentication_jwt`. Grant those users access to the app's data.
#' The issuer, audience, scopes and username claim depend on that setup.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' Connections require TLS with certificate and hostname verification.
#' Driver browser sign-in, keyring credentials and option files are disabled;
#' shinyOAuth handles sign-in and token renewal.
#'
#' A changed access token replaces the connection on the next `con()` call.
#' Token renewal does not rerun completed reactive queries. Account or
#' username changes, sign-out, lost permissions and session end close the
#' connection. Failed queries are not replayed. Finish results and
#' transactions before obtaining another connection after token renewal.
#' @examples
#' \dontrun{
#' con <- oauth_db_singlestore(
#'   auth$connection,
#'   server = "workspace.example.singlestore.com",
#'   database = "reporting",
#'   ssl_ca = "path/to/ca.pem"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER() AS database_user")
#' })
#' }
#' @seealso `vignette("singlestore", package = "shinyOAuthDB")` for database
#'   setup, sign-in configuration and a complete Shiny app.
#' @export
oauth_db_singlestore <- function(
  authorization,
  server,
  database = NULL,
  ...,
  ssl_ca,
  user = "*",
  driver = "SingleStore ODBC Unicode Driver",
  port = 3306L,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9.-]*$", server)) {
    .odb_abort(
      "server must be one SQL endpoint hostname or IPv4 address, without a protocol or port."
    )
  }
  if (
    !is.numeric(port) ||
      length(port) != 1L ||
      !is.finite(port) ||
      port < 1 ||
      port > 65535 ||
      port != floor(port)
  ) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  .odb_string(database, "database", optional = TRUE)
  .odb_string(driver, "driver")
  .odb_string(ssl_ca, "ssl_ca")
  ca_path <- as.character(ssl_ca)
  if (.odb_odbc_quoted(ca_path)) {
    ca_path <- substr(ca_path, 2L, nchar(ca_path) - 1L)
  }
  if (!nzchar(trimws(ca_path))) {
    .odb_abort("ssl_ca must name a nonempty CA certificate file path.")
  }
  if (!is.function(user)) {
    .odb_string(user, "user")
  }
  username <- function() {
    value <- if (is.function(user)) user() else user
    .odb_string(value, "user")
    .odb_odbc_values(list(user = value))
    value
  }
  options <- .odb_options(list(...), blocked = character())
  allowed <- c(
    "timeout",
    "timezone",
    "timezone_out",
    "bigint",
    "encoding",
    "name_encoding",
    "interruptible",
    "NO_CACHE",
    "FORWARDONLY",
    "COMPAT_MODE"
  )
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(
      "Only the documented result and timeout options are accepted in ...; authentication, routing, reconnect and TLS settings cannot be overridden."
    )
  }
  .odb_odbc_values(c(
    list(driver = driver, database = database, ssl_ca = ssl_ca),
    if (!is.function(user)) list(user = user),
    options
  ))
  .odb_bind(
    authorization,
    .odb_backend_singlestore,
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
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_singlestore <- function(
  token,
  server,
  database,
  user,
  driver,
  port,
  ssl_ca,
  options
) {
  bearer <- token()
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", bearer)) {
    .odb_abort(
      "SingleStore requires a signed JWT access token accepted by its JWT configuration.",
      "invalid_credential"
    )
  }
  # SingleStore's reported DBMS name otherwise selects generic SQL quoting.
  args <- list(
    drv = odbc::odbc(),
    dbms.name = "MySQL",
    driver = driver,
    SERVER = server,
    PORT = port,
    UID = user(),
    JWT = bearer,
    SSLCA = ssl_ca,
    SSLVERIFY = 1L,
    BROWSER_SSO = 0L,
    IGNORE_KEYRING_SSO = 1L,
    USE_MYCNF = 0L,
    AUTO_RECONNECT = 0L,
    NO_PROMPT = 1L
  )
  if (!is.null(database)) {
    args$DATABASE <- database
  }
  .odb_odbc_connect(c(args, options))
}
