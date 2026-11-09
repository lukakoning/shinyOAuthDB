#' Set up Google sign-in for Cloud SQL
#'
#' Create a Google OAuth client for Cloud SQL IAM database authentication.
#' Pass it to shinyOAuth's UI and server modules, then create the PostgreSQL
#' connection helper inside `server()`.
#'
#' @inheritParams oauth_db_bigquery_client
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register a Web OAuth client with the app's exact redirect URI. The default
#' scopes request identity and Cloud SQL login, without Cloud SQL administration.
#' Google sign-in and token renewal use shinyOAuth; the database helper doesn't
#' read Application Default Credentials or start the Cloud SQL Auth Proxy.
#' @examples
#' \dontrun{
#' client <- oauth_db_cloud_sql_client(
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_cloud_sql_postgres()].
#'   `vignette("cloud-sql", package = "shinyOAuthDB")` has setup and a complete app.
#' @family sign-in configuration
#' @export
oauth_db_cloud_sql_client <- function(
  client_id,
  redirect_uri,
  client_secret,
  ...,
  provider = shinyOAuth::oauth_provider_google(),
  scopes = c(
    "openid",
    "email",
    "https://www.googleapis.com/auth/sqlservice.login"
  )
) {
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes,
    ...
  )
}

#' Query Cloud SQL for PostgreSQL as the signed-in user
#'
#' Open a Cloud SQL for PostgreSQL connection with the visitor's Google access
#' token as the IAM database password. Queries work with DBI and dbplyr.
#'
#' @inheritParams oauth_db_connect
#' @param host One database hostname matching its TLS server certificate.
#' @param dbname Database name.
#' @param user IAM database username, or a function returning it for the selected
#'   account. For a Google user, this is their full email address. The server
#'   checks that the token belongs to that IAM identity.
#' @param port Database TCP port.
#' @param hostaddr Optional server IP address. `host` still supplies the name
#'   checked against the certificate.
#' @param sslrootcert Trusted server CA certificate file, or `NULL` for libpq's
#'   configured trust store.
#' @param sslcert,sslkey Optional client certificate and private key files.
#'   Supply both if the instance requires a client certificate.
#' @param required_scopes OAuth scopes to check before opening a connection.
#'   Defaults to Google's Cloud SQL login scope. Set explicitly when a custom
#'   client uses an alternative accepted scope; this check doesn't grant IAM
#'   or database privileges.
#' @param ... RPostgres options: `bigint`, `check_interrupts`, `timezone`,
#'   `timezone_out`, `connect_timeout`, `application_name`, or TCP keepalives
#'   (`keepalives`, `keepalives_idle`, `keepalives_interval`, `keepalives_count`,
#'   `tcp_user_timeout`). Authentication and TLS settings cannot be overridden.
#' @return A reactive function returning a native RPostgres DBI connection.
#' @details
#' Enable Cloud SQL IAM database authentication, add the user's IAM account
#' or group, grant Cloud SQL Instance User, and grant SQL privileges separately.
#' Use [oauth_db_cloud_sql_client()] for Google sign-in. The app host needs a
#' direct network route to the instance and a hostname matching its certificate.
#' Shared or customer-managed server CAs can provide such DNS names; see the
#' source guide for per-instance CA restrictions.
#'
#' Install RPostgres linked to libpq 16 or later. Connections require password
#' authentication and verified TLS (`sslmode = "verify-full"`), with GSS
#' encryption disabled. Unset `PGSERVICE` and `PGSERVICEFILE`; connection service
#' files cannot supply alternative settings.
#'
#' Create the helper inside `server()` and get `connection <- con()` before
#' each operation. When the token changes, the next `con()` call closes the old
#' connection and opens one with current credentials. Ordinary renewal doesn't
#' replay completed reactive queries. Finish a transaction on the connection
#' that started it. Account changes, permission loss, sign-out and session end
#' close the managed connection.
#'
#' The helper uses manual IAM database authentication with visitor tokens.
#' It doesn't use a proxy's automatic IAM login or the hosting account's
#' credentials. Cloud SQL MySQL and SQL Server aren't supported by this helper.
#' @examples
#' \dontrun{
#' con <- oauth_db_cloud_sql_postgres(
#'   auth$connection, host = "db.example.org", dbname = "reporting",
#'   user = "analyst@example.org", sslrootcert = "server-ca.pem"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user")
#' })
#' }
#' @seealso [oauth_db_cloud_sql_client()].
#'   `vignette("cloud-sql", package = "shinyOAuthDB")`.
#' @family database connections
#' @export
oauth_db_cloud_sql_postgres <- function(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 5432L,
  hostaddr = NULL,
  sslrootcert = NULL,
  sslcert = NULL,
  sslkey = NULL,
  target = NULL,
  required_scopes = "https://www.googleapis.com/auth/sqlservice.login",
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("RPostgres")
  .odb_string(host, "host")
  if (grepl("[,/\\\\[:space:];={}\"']", host)) {
    .odb_abort("host must be one TCP hostname or IP address.")
  }
  .odb_string(dbname, "dbname")
  if (grepl("[=[:cntrl:]]|://", dbname)) {
    .odb_abort("dbname must be a database name, not a connection string.")
  }
  if (
    !is.numeric(port) ||
      length(port) != 1L ||
      is.na(port) ||
      !is.finite(port) ||
      port < 1 ||
      port > 65535 ||
      port != floor(port)
  ) {
    .odb_abort("port must be a valid TCP port.")
  }
  .odb_string(hostaddr, "hostaddr", optional = TRUE)
  if (!is.null(hostaddr) && !grepl("^[0-9A-Fa-f:.]+$", hostaddr)) {
    .odb_abort("hostaddr must be one IP address.")
  }
  .odb_string(sslrootcert, "sslrootcert", optional = TRUE)
  .odb_string(sslcert, "sslcert", optional = TRUE)
  .odb_string(sslkey, "sslkey", optional = TRUE)
  if (xor(is.null(sslcert), is.null(sslkey))) {
    .odb_abort("Supply both the client certificate and its private key.")
  }
  validate_user <- function(value) {
    .odb_string(value, "user")
    if (grepl("[[:cntrl:]]", value)) {
      .odb_abort("user cannot contain control characters.")
    }
    value
  }
  if (!is.function(user)) {
    validate_user(user)
  }
  username <- function() validate_user(if (is.function(user)) user() else user)
  options <- .odb_options(list(...), blocked = character())
  allowed <- c(
    "bigint",
    "check_interrupts",
    "timezone",
    "timezone_out",
    "connect_timeout",
    "application_name",
    "keepalives",
    "keepalives_idle",
    "keepalives_interval",
    "keepalives_count",
    "tcp_user_timeout"
  )
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(paste0(
      "Only documented result and timeout options are accepted in ...; ",
      "authentication, connection identity and TLS settings cannot be overridden."
    ))
  }
  .odb_bind(
    authorization,
    .odb_backend_cloud_sql_postgres,
    settings = list(
      host = host,
      dbname = dbname,
      port = as.integer(port),
      hostaddr = hostaddr,
      sslrootcert = sslrootcert,
      sslcert = sslcert,
      sslkey = sslkey
    ),
    user = username,
    options = options,
    identity_key = username,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_cloud_sql_postgres <- function(token, settings, user, options) {
  if (any(nzchar(Sys.getenv(c("PGSERVICE", "PGSERVICEFILE"))))) {
    .odb_abort("Unset PGSERVICE and PGSERVICEFILE for Cloud SQL connections.")
  }
  driver <- RPostgres::Postgres()
  if (DBI::dbGetInfo(driver)$client.version < package_version("16.0")) {
    .odb_abort(
      "Cloud SQL PostgreSQL requires RPostgres linked to libpq 16 or later to enforce token authentication.",
      "missing_dependency"
    )
  }
  args <- c(
    list(
      drv = driver,
      user = user(),
      password = token(),
      sslmode = "verify-full",
      gssencmode = "disable",
      require_auth = "password"
    ),
    settings[!vapply(settings, is.null, logical(1))],
    options
  )
  do.call(DBI::dbConnect, args)
}
