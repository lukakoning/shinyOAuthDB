#' Query StarRocks as the signed-in user
#'
#' Open a DBI connection to StarRocks using its JWT authentication plugin
#' and MySQL Connector/ODBC's OpenID Connect client plugin.
#'
#' @inheritParams oauth_db_connect
#' @param server One StarRocks frontend hostname or address.
#' @param database Default StarRocks database.
#' @param user StarRocks username, or a reactive function returning it.
#'   The server must map the token's principal claim to this username.
#' @param driver Registered MySQL Connector/ODBC driver name. Some driver
#'   managers also accept a library path.
#'   Install version 9.2 or later, including its OpenID Connect plugin.
#' @param port MySQL protocol port, default `9030`.
#' @param ssl_ca Trusted CA certificate file, or `NULL` for driver defaults.
#' @param plugin_dir Directory containing the driver's authentication plugins,
#'   or `NULL` for its installed default.
#' @param ... Connection options: `timeout`, `timezone`, `timezone_out`,
#'   `bigint`, `encoding`, `name_encoding`, `interruptible`, `readtimeout`,
#'   `writetimeout`, `NO_CACHE`, `FORWARD_CURSOR`, `NO_CATALOG`, `NO_SCHEMA`,
#'   or `DFLT_BIGINT_BIND_STR`.
#' @return A reactive function returning an odbc DBI connection.
#' @details
#' Configure StarRocks 3.5 or later with `authentication_jwt` or a JWT security
#' integration, a trusted JWKS, issuer, audience, and principal claim. Configure
#' shinyOAuth to obtain a JWT access token accepted by that integration.
#' This helper supplies the access token; it does not substitute an ID token
#' or launch the driver's own browser flow.
#'
#' The driver reads the token from a temporary file during synchronous
#' connection opening. The file is created in a private temporary directory
#' and removed on success, error, or interrupt. On Windows its access rules
#' inherit from R's temporary directory; use a private user temporary location.
#' TLS verifies the server identity. DSNs, option files, and competing
#' credentials cannot be supplied through `...`.
#'
#' Create the helper inside `server()` and call `con()` before each operation.
#' Valid SQL sessions survive ordinary token renewal; account or username
#' changes and sign-out close them. Reopen a broken connection through `con()`;
#' the original token file no longer exists after connection opening.
#' @examples
#' \dontrun{
#' con <- oauth_db_starrocks(auth$connection,
#'   server = "starrocks.example.org", database = "reporting", user = "alice",
#'   driver = "MySQL ODBC 9.2 Unicode Driver", ssl_ca = "path/to/ca.pem")
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER()")
#' })
#' }
#' @seealso `vignette("starrocks", package = "shinyOAuthDB")`.
#' @family database connections
#' @export
oauth_db_starrocks <- function(
  authorization, server, database, user, driver, ..., port = 9030L,
  ssl_ca = NULL, plugin_dir = NULL, target = NULL, required_scopes = character(),
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  if (grepl("[,/\\\\[:space:]]", server)) .odb_abort("server must be one TCP hostname or address.")
  .odb_string(database, "database")
  .odb_string(driver, "driver")
  .odb_string(ssl_ca, "ssl_ca", optional = TRUE)
  .odb_string(plugin_dir, "plugin_dir", optional = TRUE)
  if (!is.numeric(port) || length(port) != 1L || !is.finite(port) ||
      port < 1 || port > 65535 || port != floor(port)) .odb_abort("port must be a valid TCP port.")
  if (!is.function(user)) .odb_string(user, "user")
  username <- function() {
    value <- if (is.function(user)) user() else user
    .odb_string(value, "user")
    .odb_odbc_values(list(user = value))
    value
  }
  options <- list(...)
  .odb_named_args(options, "StarRocks options")
  allowed <- c("timeout", "timezone", "timezone_out", "bigint", "encoding", "name_encoding",
    "interruptible", "readtimeout", "writetimeout", "NO_CACHE", "FORWARD_CURSOR",
    "NO_CATALOG", "NO_SCHEMA", "DFLT_BIGINT_BIND_STR")
  if (length(setdiff(names(options), allowed))) {
    .odb_abort("Only the documented result, timeout, and cursor options are accepted in ...; authentication, identity and TLS settings cannot be overridden.")
  }
  .odb_odbc_values(c(list(server = server, database = database, driver = driver,
    SSLCA = ssl_ca, PLUGIN_DIR = plugin_dir), options))
  .odb_bind(authorization, .odb_backend_starrocks, server = server, database = database,
    user = username, driver = driver, port = as.integer(port), ssl_ca = ssl_ca,
    plugin_dir = plugin_dir, options = options, identity_key = username,
    target = target, required_scopes = required_scopes, min_valid_for = min_valid_for, session = session)
}

.odb_backend_starrocks <- function(token, server, database, user, driver, port,
                                    ssl_ca, plugin_dir, options) {
  value <- token()
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", value)) {
    .odb_abort("StarRocks requires a signed JWT access token accepted by its JWT integration.", "invalid_credential")
  }
  directory <- tempfile("shinyOAuthDB-starrocks-")
  if (!dir.create(directory, mode = "0700")) .odb_abort("Cannot create the StarRocks token directory.")
  directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  if (!identical(dirname(directory), parent)) .odb_abort("Invalid StarRocks temporary directory.")
  path <- file.path(directory, "token.jwt")
  on.exit({ unlink(path); unlink(directory, recursive = TRUE) }, add = TRUE)
  writeBin(charToRaw(value), path)
  if (.Platform$OS.type != "windows" && !Sys.chmod(path, mode = "0600")) {
    .odb_abort("Cannot restrict access to the StarRocks token file.")
  }
  # A password-authenticated account must not succeed with an empty password.
  fallback <- paste0("shinyOAuthDB-disabled-", paste(format(openssl::rand_bytes(24)), collapse = ""))
  args <- list(drv = odbc::odbc(), driver = driver, SERVER = server, DATABASE = database,
    UID = user(), PWD = fallback, PORT = port, SSLMODE = "VERIFY_IDENTITY",
    USE_MYCNF = 0L, NO_PROMPT = 1L, MULTI_HOST = 0L, ENABLE_DNS_SRV = 0L)
  args[["openid-token-file"]] <- if (grepl("[;{}]", path)) odbc::quote_value(path) else path
  if (!is.null(ssl_ca)) args$SSLCA <- ssl_ca
  if (!is.null(plugin_dir)) args$PLUGIN_DIR <- plugin_dir
  do.call(DBI::dbConnect, c(args, options))
}
