#' Query SAP HANA as the signed-in user
#'
#' Open a DBI connection to SAP HANA or SAP HANA Cloud using the visitor's
#' JWT access token. HANA maps the token's external identity to a database
#' user and applies that user's privileges.
#'
#' @inheritParams oauth_db_connect
#' @param server One HANA SQL endpoint hostname or IPv4 address, without a
#'   protocol or port.
#' @param database Optional tenant database name. `NULL` uses the database
#'   selected by the SQL endpoint. HANA Cloud normally needs only its endpoint.
#' @param port SQL endpoint port, default `443` for HANA Cloud. For self-hosted
#'   HANA, use the SQL port supplied by your administrator.
#' @param schema Optional initial SQL schema. `NULL` uses the user's default.
#' @param driver Installed SAP HANA ODBC driver name, default `"HDBODBC"`,
#'   or a library path supported by the driver manager. Install a current
#'   SAP HANA Client with JWT authentication support.
#' @param ssl_trust_store Optional trust-store path for the SAP HANA Client's
#'   TLS provider. `NULL` uses the client's configured trust store.
#' @param ... Result options `timeout`, `timezone`, `timezone_out`, `bigint`,
#'   `encoding`, `name_encoding`, and `interruptible`. Native authentication,
#'   routing, reconnect and TLS settings cannot be overridden.
#' @return A reactive function returning an odbc DBI connection.
#' @details
#' Install odbc and SAP HANA Client's ODBC driver. Configure a JWT provider,
#'   signing-certificate trust, external-identity mappings and user privileges
#'   in the target database. The OAuth provider must issue a JWT access token
#'   accepted by this configuration. Browser SSO for SAP BTP alone does not
#'   establish SQL access. There is no universal SAP scope or token audience.
#'
#' The helper supplies the token as `PWD` with an empty `UID` and restricts
#'   `authenticationMethods` to `jwt`. TLS encryption, certificate validation
#'   and matching of the endpoint hostname are required. DSNs, saved user
#'   credentials, session cookies and alternate authentication methods cannot
#'   be selected through this helper.
#'
#' Create the helper inside `server()` and call `connection <- con()` before
#'   each query. Valid SQL sessions survive ordinary token renewal. Account
#'   changes, permission loss, sign-out and Shiny session end close them.
#'   Native automatic reconnect is disabled; reopen a broken connection
#'   through `con()` to supply a current token. Failed queries are not replayed.
#' @examples
#' \dontrun{
#' con <- oauth_db_hana(
#'   auth$connection,
#'   server = "example.hana.prod-eu10.hanacloud.ondemand.com",
#'   schema = "REPORTING"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER AS DATABASE_USER FROM DUMMY")
#' })
#' }
#' @seealso `vignette("hana", package = "shinyOAuthDB")` for sign-in,
#'   database configuration and a complete Shiny app.
#' @family database connections
#' @export
oauth_db_hana <- function(
  authorization,
  server,
  database = NULL,
  ...,
  port = 443L,
  schema = NULL,
  driver = "HDBODBC",
  ssl_trust_store = NULL,
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
  .odb_string(schema, "schema", optional = TRUE)
  .odb_string(driver, "driver")
  .odb_string(ssl_trust_store, "ssl_trust_store", optional = TRUE)
  options <- .odb_options(list(...), blocked = character())
  allowed <- c(
    "timeout",
    "timezone",
    "timezone_out",
    "bigint",
    "encoding",
    "name_encoding",
    "interruptible"
  )
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(
      "Only the documented result and timeout options are accepted in ...; authentication, routing, reconnect and TLS settings cannot be overridden."
    )
  }
  .odb_odbc_values(c(
    list(
      driver = driver,
      database = database,
      schema = schema,
      ssl_trust_store = ssl_trust_store
    ),
    options
  ))
  .odb_bind(
    authorization,
    .odb_backend_hana,
    server = server,
    port = as.integer(port),
    database = database,
    schema = schema,
    driver = driver,
    ssl_trust_store = ssl_trust_store,
    options = options,
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_hana <- function(
  token,
  server,
  port,
  database,
  schema,
  driver,
  ssl_trust_store,
  options
) {
  bearer <- token()
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", bearer)) {
    .odb_abort(
      "SAP HANA requires a signed JWT access token accepted by its JWT provider.",
      "invalid_credential"
    )
  }
  context <- list(
    databaseName = database,
    currentSchema = schema,
    sslTrustStore = ssl_trust_store
  )
  context <- context[!vapply(context, is.null, logical(1))]
  do.call(
    DBI::dbConnect,
    c(
      list(
        drv = odbc::odbc(),
        driver = driver,
        serverNode = paste0(server, ":", port),
        UID = "",
        PWD = bearer,
        authenticationMethods = "jwt",
        encrypt = "true",
        sslValidateCertificate = "true",
        sslHostNameInCertificate = server,
        reconnect = "false"
      ),
      context,
      options
    )
  )
}
