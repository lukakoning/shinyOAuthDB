#' Query CockroachDB as the signed-in user
#'
#' Read CockroachDB data using each visitor's JWT access token and database
#' permissions. Works with self-hosted and cloud clusters configured for
#' cluster SSO using JWTs. Returns an RPostgres connection for DBI or dbplyr.
#'
#' @inheritParams oauth_db_connect
#' @param host One CockroachDB SQL hostname or IP address.
#' @param dbname Database name, not a connection string or URI.
#' @param user SQL username, or a function deriving it from the selected
#'   sign-in. The cluster must map the token's principal to that user.
#' @param port SQL port, default `26257`.
#' @param sslrootcert CA certificate bundle path, or `NULL` for libpq's
#'   configured bundle.
#' @param connect_timeout Connection timeout in whole seconds, at least two.
#' @param ... RPostgres result options (`bigint`, `check_interrupts`,
#'   `timezone`, `timezone_out`), `application_name`, or TCP keepalive options.
#'   Authentication, connection identity and TLS settings cannot be overridden.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install RPostgres linked to libpq 16 or later. Configure the cluster's
#' `server.jwt_authentication` settings for your provider's issuer, signing
#' keys, audience and principal claim. Request a JWT-format access token
#' intended for the cluster. Opaque access tokens and ID tokens aren't used
#' by this helper. There is no universal CockroachDB OAuth client preset.
#'
#' Connections use verified TLS and CockroachDB's JWT-as-password protocol,
#' with `--crdb:jwt_auth_enabled=true`. The helper requires password
#' authentication from the server and doesn't use client certificate or
#' trust authentication. Unset `PGSERVICE` and `PGSERVICEFILE` before use.
#' This helper doesn't use the newer SASL OAUTHBEARER protocol.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' After token renewal, the next call replaces the connection with current
#' credentials without replaying completed reactive queries. Account or
#' username changes, lost permissions, sign-out and session end close it.
#' Complete a transaction on the connection that started it; get the next
#' operation's connection through `con()`.
#' @examples
#' \dontrun{
#' con <- oauth_db_cockroachdb(
#'   auth$connection,
#'   host = "cluster.example.org", dbname = "reporting",
#'   user = function() {
#'     reference <- shiny::req(auth$connection())
#'     identity <- reference$identity(claims = "preferred_username")
#'     shiny::req(identity$id_token_claims$preferred_username)
#'   },
#'   sslrootcert = "path/to/ca.pem"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user")
#' })
#' }
#' @seealso `vignette("cockroachdb", package = "shinyOAuthDB")`.
#' @export
oauth_db_cockroachdb <- function(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 26257L,
  sslrootcert = NULL,
  connect_timeout = 5L,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_postgres_string(host, "host")
  if (grepl("[,/=@[:space:]]", host) || startsWith(host, "\\")) {
    .odb_abort("host must be one TCP hostname or address.")
  }
  .odb_postgres_string(dbname, "dbname")
  if (grepl("=|^postgres(ql)?://", dbname)) {
    .odb_abort(
      "dbname must be a database name, not a connection string or URI."
    )
  }
  if (!is.function(user)) {
    .odb_postgres_string(user, "user")
  }
  username <- function() {
    value <- if (is.function(user)) user() else user
    .odb_postgres_string(value, "user")
    value
  }
  if (!is.null(sslrootcert)) {
    .odb_postgres_string(sslrootcert, "sslrootcert")
  }
  if (
    !is.numeric(port) ||
      length(port) != 1L ||
      !is.finite(port) ||
      port < 1 ||
      port > 65535 ||
      port != floor(port)
  ) {
    .odb_abort("port must be one valid TCP port.")
  }
  if (
    !is.numeric(connect_timeout) ||
      length(connect_timeout) != 1L ||
      !is.finite(connect_timeout) ||
      connect_timeout < 2 ||
      connect_timeout > .Machine$integer.max ||
      connect_timeout != floor(connect_timeout)
  ) {
    .odb_abort(
      "connect_timeout must be a whole number of at least two seconds."
    )
  }
  options <- list(...)
  .odb_named_args(options, "CockroachDB options in ...")
  allowed <- c(
    "bigint",
    "check_interrupts",
    "timezone",
    "timezone_out",
    "application_name",
    "keepalives",
    "keepalives_idle",
    "keepalives_interval",
    "keepalives_count",
    "tcp_user_timeout"
  )
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(
      "Only RPostgres result, application_name and TCP keepalive options are accepted in ...; authentication, connection identity and TLS settings cannot be overridden."
    )
  }
  .odb_require("RPostgres")
  if (
    DBI::dbGetInfo(RPostgres::Postgres())$client.version <
      package_version("16.0")
  ) {
    .odb_abort(
      "CockroachDB JWT authentication requires RPostgres linked to libpq 16 or later to enforce token authentication.",
      "missing_dependency"
    )
  }
  .odb_bind(
    authorization,
    .odb_backend_cockroachdb,
    host = host,
    dbname = dbname,
    user = username,
    port = as.integer(port),
    sslrootcert = sslrootcert,
    connect_timeout = as.integer(connect_timeout),
    options = options,
    identity_key = username,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_cockroachdb <- function(
  token,
  host,
  dbname,
  user,
  port,
  sslrootcert,
  connect_timeout,
  options
) {
  if (any(nzchar(Sys.getenv(c("PGSERVICE", "PGSERVICEFILE"))))) {
    .odb_abort(
      "Unset PGSERVICE and PGSERVICEFILE for CockroachDB JWT authentication."
    )
  }
  value <- token()
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", value)) {
    .odb_abort(
      "CockroachDB requires a signed JWT access token.",
      "invalid_credential"
    )
  }
  args <- list(
    drv = RPostgres::Postgres(),
    host = host,
    dbname = dbname,
    user = user(),
    port = port,
    password = value,
    sslmode = "verify-full",
    gssencmode = "disable",
    require_auth = "password",
    options = "--crdb:jwt_auth_enabled=true",
    connect_timeout = connect_timeout
  )
  if (!is.null(sslrootcert)) {
    args$sslrootcert <- sslrootcert
  }
  do.call(DBI::dbConnect, c(args, options))
}
