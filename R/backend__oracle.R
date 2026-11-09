#' Query Oracle Database as the signed-in user
#'
#' Read Oracle data in a Shiny app with each visitor's database permissions.
#' Oracle checks the visitor's access token and maps their identity to
#' database privileges. The helper opens a DBI connection for SQL or dbplyr.
#'
#' @inheritParams oauth_db_connect
#' @param host One Oracle TCPS listener hostname or IP address.
#' @param service_name Oracle database service name, not a SID or TNS alias.
#' @param driver Registered Oracle ODBC driver name, or its library path when
#'   supported by the driver manager. Install a client that supports the
#'   database's OAuth integration; newer integrations need a current client.
#' @param authorization_model `"global"` (the default) for a mapped global
#'   database user, or `"end_user"` for an individual Oracle Deep Data
#'   Security context. Choose the model configured by your administrator;
#'   see Details.
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
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and Oracle Instant Client's Basic and ODBC packages. The
#' database must trust your provider and audience, map users to database
#' privileges, and use a compatible Oracle client. The Oracle vignette
#' explains the provider-specific setup.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' Connections use encrypted TCPS transport with server certificate checks.
#' Use a wallet when the service requires one.
#' @section Authorization models:
#' The `"global"` model connects as the Oracle global user mapped to the
#' external identity. The helper checks for `TOKEN_GLOBAL` authentication.
#'
#' The `"end_user"` model requires Oracle Deep Data Security direct logon and
#' the jsonlite package. Oracle must establish an end-user context whose
#' issuer, subject and audience match the supplied JWT. Missing or mismatched
#' context is an error; the helper doesn't fall back to a global-schema login.
#'
#' Keep Entra's `/.default` consent marker in the client configuration. Use
#' the exact granted database scope in `required_scopes`.
#' @section Connection lifetime:
#' Global-schema connections stay open through token renewal. End-user
#' connections reopen on the next `con()` call after a token change, so new
#' role claims reach the database. Sign-out, account changes and session
#' end close both types. Reopen broken connections through `con()`.
#'
#' The Oracle driver reads the token from a temporary file, which is removed
#' after connecting. On Windows, keep R's temporary directory private to
#' the app's operating-system user. For Oracle web APIs, use
#' [oauth_db_oracle_ords_api()].
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
  authorization_model = c("global", "end_user"),
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  authorization_model <- match.arg(authorization_model)
  if (authorization_model == "end_user") {
    .odb_require("jsonlite")
  }
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
    authorization_model = authorization_model,
    options = options,
    target = target,
    required_scopes = required_scopes,
    cache_key = if (authorization_model == "end_user") {
      function(token) openssl::sha256(charToRaw(token()))
    },
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
  options,
  authorization_model
) {
  bearer <- token()
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", bearer)) {
    .odb_abort(
      "Oracle requires a signed JWT access token accepted by the database.",
      "invalid_credential"
    )
  }
  expected <- if (authorization_model == "end_user") {
    .odb_oracle_jwt_identity(bearer)
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
  connection <- .odb_odbc_connect(
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
  if (authorization_model == "global") {
    method <- DBI::dbGetQuery(
      connection,
      "SELECT SYS_CONTEXT('USERENV', 'AUTHENTICATION_METHOD') AS AUTH_METHOD FROM DUAL"
    )
    if (!identical(.odb_oracle_scalar(method), "TOKEN_GLOBAL")) {
      .odb_oracle_verification_failed()
    }
  } else {
    context <- DBI::dbGetQuery(
      connection,
      paste0(
        "SELECT JSON_OBJECT(",
        "'iss' VALUE ORA_END_USER_CONTEXT.USER.TOKEN.iss, ",
        "'sub' VALUE ORA_END_USER_CONTEXT.USER.TOKEN.sub, ",
        "'aud' VALUE ORA_END_USER_CONTEXT.USER.TOKEN.aud ",
        "RETURNING VARCHAR2(4000)) AS TOKEN_CLAIMS FROM DUAL"
      )
    )
    claims <- .odb_oracle_scalar(context)
    actual <- tryCatch(
      .odb_oracle_identity(jsonlite::parse_json(claims)),
      error = function(e) NULL
    )
    if (is.null(actual) || !identical(actual, expected)) {
      .odb_oracle_verification_failed()
    }
  }
  verified <- TRUE
  connection
}

.odb_oracle_scalar <- function(value) {
  if (
    is.data.frame(value) &&
      identical(dim(value), c(1L, 1L)) &&
      is.character(value[[1L]]) &&
      !is.na(value[[1L]]) &&
      nzchar(value[[1L]])
  ) {
    value[[1L]]
  }
}

.odb_oracle_verification_failed <- function() {
  .odb_abort(
    "Oracle did not confirm the selected token authorization model. Check the client version, identity provider and database user/data-role mappings.",
    "invalid_credential"
  )
}

.odb_oracle_identity <- function(claims) {
  scalar <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  }
  if (
    !is.list(claims) ||
      is.null(names(claims)) ||
      anyDuplicated(names(claims)) ||
      !scalar(claims$iss) ||
      !scalar(claims$sub)
  ) {
    return(NULL)
  }
  audience <- claims$aud
  if (scalar(audience)) {
    audience <- list(audience)
  }
  if (
    !is.list(audience) ||
      !is.null(names(audience)) ||
      !length(audience) ||
      !all(vapply(audience, scalar, logical(1)))
  ) {
    return(NULL)
  }
  list(iss = claims$iss, sub = claims$sub, aud = sort(unique(unlist(audience))))
}

.odb_oracle_jwt_identity <- function(bearer) {
  payload <- strsplit(bearer, ".", fixed = TRUE)[[1L]][[2L]]
  claims <- tryCatch(
    {
      if (nchar(payload, type = "bytes") > 65536L) {
        stop("Oversized payload")
      }
      payload <- chartr("-_", "+/", payload)
      payload <- paste0(payload, strrep("=", (4L - nchar(payload) %% 4L) %% 4L))
      payload <- rawToChar(openssl::base64_decode(payload))
      Encoding(payload) <- "UTF-8"
      jsonlite::parse_json(payload)
    },
    error = function(e) NULL
  )
  identity <- .odb_oracle_identity(claims)
  if (is.null(identity)) {
    .odb_abort(
      "End-user verification requires a JWT with nonempty iss, sub and aud claims.",
      "invalid_credential"
    )
  }
  identity
}
