#' Query Oracle Database as the signed-in user
#'
#' Open an Oracle ODBC connection with the visitor's OAuth access token.
#' The database validates the provider's JWT and applies its configured
#' global-user or Oracle Deep Data Security authorization model.
#'
#' @inheritParams oauth_db_connect
#' @param host One Oracle TCPS listener hostname or IP address.
#' @param service_name Oracle database service name, not a SID or TNS alias.
#' @param driver Registered Oracle ODBC driver name, or its library path when
#'   supported by the driver manager. Install a client that supports the
#'   database's OAuth integration; newer integrations need a current client.
#' @param authorization_model `"global"` requires Oracle to report
#'   `TOKEN_GLOBAL` authentication, preserving the global-schema model used
#'   by existing Entra configurations. `"end_user"` requires Oracle Deep
#'   Data Security to expose system-managed token claims matching the
#'   submitted JWT's issuer, subject and audience. It never falls back to
#'   global-schema privileges. Use this for configured OCI IAM OAuth and
#'   Keycloak direct-logon deployments.
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
#' database must trust the token's provider and audience and map the visitor
#' to a global schema or Deep Data Security data roles. Supported routes
#' include Microsoft Entra, OCI IAM Identity Domains OAuth, and the
#' configurable OAuth provider documented for Keycloak in Oracle 26ai.
#' Server and client version requirements differ between these integrations;
#' a JWT from an unconfigured provider does not establish database access.
#' See `vignette("oracle", package = "shinyOAuthDB")` for sign-in setup.
#'
#' Create the helper inside `server()` and call `con()` before each operation.
#' Global-schema sessions survive ordinary token renewal. End-user sessions
#' are reopened on access when the token changes, so new identity and role
#' claims reach the database without replaying completed queries. Account
#' changes, sign-out, permission loss and session end close the connection.
#' A broken connection is reopened with the current token on access.
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
#' helper verifies the selected authorization model and disconnects on
#' failure. In `"end_user"` mode, jsonlite is also required. Local JWT
#' decoding identifies the expected claims; Oracle verifies the signature
#' and establishes the system-managed context. DSNs, alternate credentials
#' and authentication overrides cannot be supplied through `...`.
#'
#' Scope names are checked literally, as with generic OAuth helpers. Keep
#' Entra's `/.default` consent marker in the client configuration, not in
#' this helper's `required_scopes`. OCI IAM proof-of-possession tokens,
#' password authentication and application-mediated two-token contexts are
#' separate mechanisms. For ORDS REST resources use [oauth_db_oracle_ords_api()].
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
