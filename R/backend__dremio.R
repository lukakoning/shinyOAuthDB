#' Query Dremio as the signed-in user
#'
#' Open a Flight SQL connection with the visitor's current OAuth access token.
#' The connection uses adbi and Apache Arrow's ADBC Flight SQL driver, and
#' supports DBI queries and Arrow results.
#'
#' @inheritParams oauth_db_connect
#' @param host One Flight SQL endpoint hostname or IPv4 address, without a
#'   protocol or port. Use a Dremio endpoint configured for TLS and bearer
#'   authentication.
#' @param port Flight SQL port, default `32010` for self-hosted Dremio.
#' @param driver Installed ADBC driver name, manifest path or shared-library
#'   path. The default `"flightsql"` selects the driver installed with
#'   `dbc install flightsql`.
#' @param ca_bundle Optional path to a PEM file containing trusted CA
#'   certificates. `NULL` uses the driver's system trust roots.
#' @param timeout Positive timeout in seconds for each Flight SQL connection,
#'   query, fetch or update RPC. This is not a deadline for an entire query.
#' @param ... Result option `bigint`, passed to adbi's `DBI::dbConnect()`
#'   method. Other native options cannot be supplied.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then use
#'   the connection with DBI. Before sign-in, it waits quietly.
#' @details
#' Install adbi, adbcdrivermanager 0.25.0 or later, and the ADBC Flight SQL
#' shared-library driver. The R packages alone do not install that driver.
#' Configure Dremio Enterprise to accept the provider's external JWT access
#' tokens and map their identities to Dremio users. An already acquired
#' Dremio OAuth access token can also be supplied through shinyOAuth.
#'
#' The helper sends the access token directly as a bearer credential. It
#' does not exchange external JWTs for Dremio tokens or run the driver's
#' OAuth flow. A browser login alone does not configure database access.
#' Dremio Cloud editions and endpoints require separate compatibility checks;
#' see `vignette("dremio", package = "shinyOAuthDB")`.
#'
#' TLS and certificate verification are required. Credentials, native OAuth
#' settings, headers, URI and TLS settings cannot be overridden in `...`.
#'
#' Create the helper inside `server()` and call `con()` before each operation.
#' A changed access token replaces the connection on its next use, without
#' replaying completed reactive queries. Account changes, permission loss,
#' sign-out and session end close the connection and outstanding results.
#' The driver holds a fixed bearer during each DBI operation; renewing the
#' Shiny token does not update an ongoing query or fetch.
#' A failed query is not replayed. Reopening loses SQL session state; a
#' submitted query may continue after the local connection closes.
#' @examples
#' \dontrun{
#' con <- oauth_db_dremio(auth$connection, host = "dremio.example.org")
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER AS database_user")
#' })
#' }
#' @seealso `vignette("dremio", package = "shinyOAuthDB")` for driver
#'   installation, provider settings and a complete Shiny app.
#' @export
oauth_db_dremio <- function(
  authorization,
  host,
  ...,
  port = 32010L,
  driver = "flightsql",
  ca_bundle = NULL,
  timeout = 30,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("adbi", version = "0.1.2")
  .odb_require("adbcdrivermanager", version = "0.25.0")
  .odb_string(host, "host")
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9.-]*$", host)) {
    .odb_abort(
      "host must be one Flight SQL hostname or IPv4 address, without a protocol or port."
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
  .odb_string(driver, "driver")
  if (grepl("[[:cntrl:]]", driver)) {
    .odb_abort("driver cannot contain control characters.")
  }
  if (
    !is.numeric(timeout) ||
      length(timeout) != 1L ||
      !is.finite(timeout) ||
      timeout <= 0
  ) {
    .odb_abort("timeout must be one positive number of seconds.")
  }
  .odb_string(ca_bundle, "ca_bundle", optional = TRUE)
  certificates <- NULL
  if (!is.null(ca_bundle)) {
    if (!file.exists(ca_bundle) || dir.exists(ca_bundle)) {
      .odb_abort("ca_bundle must name an existing PEM certificate file.")
    }
    certificates <- tryCatch(
      paste(readLines(ca_bundle, warn = FALSE), collapse = "\n"),
      error = function(e) .odb_abort("Cannot read the Flight SQL CA bundle.")
    )
    if (!grepl("-----BEGIN CERTIFICATE-----", certificates, fixed = TRUE)) {
      .odb_abort("ca_bundle must contain PEM certificates.")
    }
  }
  options <- .odb_options(list(...), blocked = character())
  if (length(setdiff(names(options), "bigint"))) {
    .odb_abort(
      "Only the result option bigint is accepted in ...; authentication, headers, routing and TLS settings cannot be overridden."
    )
  }
  .odb_bind(
    authorization,
    .odb_backend_dremio,
    host = host,
    port = as.integer(port),
    driver = driver,
    certificates = certificates,
    timeout = timeout,
    options = options,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_dremio <- function(
  token,
  host,
  port,
  driver,
  certificates,
  timeout,
  options
) {
  args <- c(
    list(
      drv = adbi::adbi(adbcdrivermanager::adbc_driver(
        driver,
        entrypoint = "AdbcDriverFlightSQLInit"
      )),
      uri = paste0("grpc+tls://", host, ":", port),
      adbc.flight.sql.authorization_header = paste("Bearer", token()),
      adbc.flight.sql.client_option.tls_skip_verify = "false",
      adbc.flight.sql.rpc.with_cookie_middleware = "false",
      adbc.flight.sql.rpc.timeout_seconds.connect = as.character(timeout),
      adbc.flight.sql.rpc.timeout_seconds.query = as.character(timeout),
      adbc.flight.sql.rpc.timeout_seconds.fetch = as.character(timeout),
      adbc.flight.sql.rpc.timeout_seconds.update = as.character(timeout)
    ),
    if (!is.null(certificates)) {
      list(adbc.flight.sql.client_option.tls_root_certs = certificates)
    },
    options
  )
  # Retain argument references, rather than bearer values, in native error calls.
  values <- lapply(seq_along(args), function(i) {
    substitute(args[[index]], list(index = i))
  })
  names(values) <- names(args)
  eval(as.call(c(list(quote(DBI::dbConnect)), values)), envir = environment())
}
