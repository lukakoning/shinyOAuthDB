#' Query Oracle Database as the signed-in user
#'
#' Open an Oracle ODBC connection with the visitor's Microsoft Entra access
#' token. Use the connection with DBI or dbplyr against an Oracle database
#' configured for Entra authentication, on your infrastructure or in the cloud.
#'
#' @inheritParams oauth_db_connect
#' @param host One Oracle TCPS listener hostname or IP address.
#' @param service_name Oracle database service name, not a SID or TNS alias.
#' @param driver Registered Oracle ODBC driver name, or its library path when
#'   supported by the driver manager. Use Oracle Instant Client with OAuth
#'   support: 19.16 or later in the 19c line, or a supported newer release.
#'   The 21c thick client does not support this integration.
#' @param port TCPS listener port. Defaults to `1522`; use the port supplied
#'   by your administrator, which may differ for self-hosted databases.
#' @param wallet_location Optional Oracle wallet directory for TLS trust or
#'   mutual TLS. `NULL` uses the Oracle client's configured trust store.
#' @param server_cert_dn Optional expected server certificate distinguished
#'   name. `NULL` uses Oracle's hostname matching. Certificate matching is
#'   always enabled.
#' @param ... Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
#'   `encoding`, `name_encoding`, or `interruptible`; Oracle ODBC options
#'   `FBS` (fetch buffer size) and `DBA` (`"R"` for read-only, `"W"` for
#'   read/write) are also accepted.
#' @return A reactive function returning an odbc DBI connection.
#' @details
#' Install odbc and Oracle Instant Client's Basic and ODBC packages. The
#' database must support and enable Microsoft Entra integration and map the
#' visitor to a global database schema. Request delegated access to
#' that database's own Entra application resource. Azure SQL tokens and
#' arbitrary OIDC tokens are not interchangeable with Oracle access tokens.
#' See `vignette("oracle", package = "shinyOAuthDB")` for sign-in setup.
#'
#' Create the helper inside `server()` and call `con()` before each operation.
#' Valid SQL sessions survive ordinary token renewal. Account changes,
#' sign-out, permission loss and session end close the connection. A broken
#' connection is reopened with the current token on the next `con()` call.
#'
#' The helper builds a separate TCPS descriptor for each connection. It sets
#' `TOKEN_AUTH=OAUTH`, supplies the token through a private temporary file,
#' and removes that file on success, error or interrupt. On Windows the
#' directory inherits R's temporary-directory access rules; run R with a
#' private user temporary directory. Shared `TNS_ADMIN`, `tnsnames.ora`, and
#' `sqlnet.ora` files are not modified.
#'
#' Oracle ODBC failover is disabled because the temporary token file is
#' removed after connection opening. Before returning a connection, the
#' helper checks that Oracle reports `TOKEN_GLOBAL` authentication and
#' disconnects otherwise. DSNs, alternate credentials and authentication
#' overrides cannot be supplied through `...`. OCI IAM proof-of-possession
#' tokens and password authentication are outside this helper's scope.
#' @examples
#' \dontrun{
#' con <- oauth_db_oracle(
#'   auth$connection,
#'   host = "database.example.org",
#'   service_name = "reporting.example.org",
#'   driver = "Oracle in instantclient_19_30"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT USER AS database_user FROM DUAL")
#' })
#' }
#' @seealso `vignette("oracle", package = "shinyOAuthDB")`.
#' @family database connections
#' @export
oauth_db_oracle <- function(
  authorization,
  host,
  service_name,
  driver,
  ...,
  port = 1522L,
  wallet_location = NULL,
  server_cert_dn = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(host, "host")
  .odb_string(service_name, "service_name")
  .odb_string(driver, "driver")
  if (!grepl("^[A-Za-z0-9._:-]+$", host)) {
    .odb_abort("host must be one TCPS listener hostname or IP address.")
  }
  if (!grepl("^[A-Za-z0-9_.#$-]+$", service_name)) {
    .odb_abort("service_name must be one Oracle service name.")
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
  .odb_oracle_text(wallet_location, "wallet_location", optional = TRUE)
  .odb_oracle_text(server_cert_dn, "server_cert_dn", optional = TRUE)
  options <- .odb_options(list(...), blocked = character())
  allowed <- c(
    "timeout",
    "timezone",
    "timezone_out",
    "bigint",
    "encoding",
    "name_encoding",
    "interruptible",
    "FBS",
    "DBA"
  )
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(
      "Only the documented result, timeout, FBS and DBA options are accepted in ...; authentication, connection identity and TLS settings cannot be overridden."
    )
  }
  .odb_odbc_values(c(list(driver = driver), options))
  .odb_bind(
    authorization,
    .odb_backend_oracle,
    host = host,
    service_name = service_name,
    driver = driver,
    port = as.integer(port),
    wallet_location = wallet_location,
    server_cert_dn = server_cert_dn,
    options = options,
    target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_oracle_text <- function(value, name, optional = FALSE) {
  .odb_string(value, name, optional = optional)
  if (!is.null(value) && grepl("[\"';{}[:cntrl:]]", value)) {
    .odb_abort(paste0(
      name,
      " cannot contain quotes, semicolons, braces or control characters."
    ))
  }
  invisible(value)
}

.odb_oracle_descriptor <- function(
  host,
  service_name,
  port,
  token_path,
  wallet_location,
  server_cert_dn
) {
  .odb_oracle_text(token_path, "Oracle token path")
  security <- paste0(
    "(AUTHENTICATION_SERVICE=NONE)",
    "(SSL_SERVER_DN_MATCH=YES)",
    "(TLS_SERVER_DN_MATCH=YES)",
    "(TOKEN_AUTH=OAUTH)",
    '(TOKEN_LOCATION="',
    token_path,
    '")'
  )
  if (!is.null(wallet_location)) {
    security <- paste0(security, '(WALLET_LOCATION="', wallet_location, '")')
  }
  if (!is.null(server_cert_dn)) {
    security <- paste0(
      security,
      '(SSL_SERVER_CERT_DN="',
      server_cert_dn,
      '")',
      '(TLS_SERVER_CERT_DN="',
      server_cert_dn,
      '")'
    )
  }
  paste0(
    "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=",
    host,
    ")(PORT=",
    port,
    "))",
    "(CONNECT_DATA=(SERVICE_NAME=",
    service_name,
    "))",
    "(SECURITY=",
    security,
    "))"
  )
}

.odb_backend_oracle <- function(
  token,
  host,
  service_name,
  driver,
  port,
  wallet_location,
  server_cert_dn,
  options
) {
  bearer <- token()
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", bearer)) {
    .odb_abort(
      "Oracle requires an Entra JWT access token.",
      "invalid_credential"
    )
  }
  directory <- tempfile("shinyOAuthDB-oracle-")
  if (!dir.create(directory, mode = "0700")) {
    .odb_abort("Cannot create the Oracle token directory.")
  }
  directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  if (!identical(dirname(directory), parent)) {
    .odb_abort("Invalid Oracle temporary directory.")
  }
  path <- file.path(directory, "token")
  on.exit(
    {
      unlink(path)
      unlink(directory, recursive = TRUE)
    },
    add = TRUE
  )
  descriptor <- .odb_oracle_descriptor(
    host,
    service_name,
    port,
    path,
    wallet_location,
    server_cert_dn
  )
  writeBin(charToRaw(bearer), path)
  if (.Platform$OS.type != "windows" && !Sys.chmod(path, mode = "0600")) {
    .odb_abort("Cannot restrict access to the Oracle token file.")
  }
  connection <- do.call(
    DBI::dbConnect,
    c(
      list(
        drv = odbc::odbc(),
        driver = driver,
        DBQ = odbc::quote_value(descriptor),
        UID = "",
        PWD = "",
        FEN = "F"
      ),
      options
    )
  )
  verified <- FALSE
  on.exit(
    {
      if (!verified) {
        tryCatch(DBI::dbDisconnect(connection), error = function(e) NULL)
      }
    },
    add = TRUE
  )
  method <- DBI::dbGetQuery(
    connection,
    "SELECT SYS_CONTEXT('USERENV', 'AUTHENTICATION_METHOD') AS AUTH_METHOD FROM DUAL"
  )
  if (
    !is.data.frame(method) ||
      !identical(dim(method), c(1L, 1L)) ||
      !identical(method[[1L]], "TOKEN_GLOBAL")
  ) {
    .odb_abort(
      "Oracle did not confirm token authentication. Check the Oracle client version and database Entra configuration.",
      "invalid_credential"
    )
  }
  verified <- TRUE
  connection
}
