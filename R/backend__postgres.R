#' Query PostgreSQL as the signed-in user
#'
#' Read PostgreSQL data in a Shiny app using each visitor's account and
#' existing database permissions. This helper uses PostgreSQL's native OAuth
#' support and opens an RPostgres connection for DBI or dbplyr queries.
#'
#' @inheritParams oauth_db_connect
#' @param host One TCP hostname or address.
#' @param dbname Database name.
#' @param user Requested database role, or a function deriving it from the
#'   selected sign-in's validated identity. PostgreSQL checks that the token
#'   may use that role according to the server's identity mapping.
#' @param issuer Exact HTTPS issuer identifier configured on PostgreSQL.
#' @param scope Space-separated scopes configured in the server's OAuth
#'   authentication rule. These scopes are also checked before connecting.
#' @param port TCP port, default `5432`.
#' @param sslrootcert CA certificate bundle path, or `NULL` for libpq defaults.
#' @param connect_timeout Connection timeout in whole seconds, at least two.
#' @param ... RPostgres result options (`bigint`, `check_interrupts`,
#'   `timezone`, `timezone_out`), `application_name`, or TCP keepalive options.
#'   Authentication and TLS options cannot be overridden.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Native OAuth requires Linux, PostgreSQL 18, and RPostgres and shinyOAuthDB
#' built against the same shared libpq 18. Install libpq without its optional
#' device-flow module; shinyOAuth handles browser sign-in and token renewal.
#' Other platforms can run the Docker demo or use [oauth_db_postgrest_api()].
#'
#' Configure the server's OAuth validator, trusted issuer and audience, and
#' the mapping from users to database roles. Connections require OAuth and
#' verified TLS. The PostgreSQL vignette has a working Keycloak configuration.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' A valid connection stays open through token renewal. Account or role
#' changes and sign-out close it. If it breaks, reopen through `con()`;
#' resetting or cloning a saved connection isn't supported.
#' @section Try the Docker demo:
#' With Docker running, call [oauth_db_demo()] to try PostgreSQL, Keycloak
#' sign-in and a Shiny app with sample data on Windows, macOS or Linux.
#' Use `oauth_db_demo(action = "files")` to copy the configuration.
#'
#' The [PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html)
#' covers the demo and setup for your own server.
#' @examples
#' \dontrun{
#' # Inside server(), with an OIDC client requesting openid, profile and database.read:
#' con <- oauth_db_postgres(
#'   auth$connection,
#'   host = "postgres.example.org", dbname = "reporting",
#'   user = function() {
#'     reference <- shiny::req(auth$connection())
#'     identity <- reference$identity(claims = "preferred_username")
#'     shiny::req(identity$id_token_claims$preferred_username)
#'   },
#'   issuer = "https://login.example.org/realms/reporting",
#'   scope = "database.read", sslrootcert = "path/to/ca.pem"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user")
#' })
#' }
#' @seealso [oauth_db_azure_postgres()] for Azure's Entra authentication.
#' @export
oauth_db_postgres <- function(
  authorization,
  host,
  dbname,
  user,
  issuer,
  scope,
  ...,
  port = 5432L,
  sslrootcert = NULL,
  connect_timeout = 5L,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  settings <- .odb_postgres_settings(
    host,
    dbname,
    issuer,
    scope,
    port,
    sslrootcert,
    connect_timeout,
    list(...)
  )
  if (!is.function(user)) {
    .odb_postgres_string(user, "user")
  }
  username <- function() {
    value <- if (is.function(user)) user() else user
    .odb_postgres_string(value, "user")
    value
  }
  .odb_postgres_runtime()
  scopes <- strsplit(scope, " ", fixed = TRUE)[[1L]]
  .odb_bind(
    authorization,
    .odb_backend_postgres_oauth,
    settings = settings,
    user = username,
    target = target,
    required_scopes = union(scopes, .odb_scopes(required_scopes)),
    identity_key = username,
    min_valid_for = min_valid_for,
    session = session,
    is_valid = .odb_postgres_connection_valid
  )
}

.odb_postgres_string <- function(value, name) {
  .odb_string(value, name)
  if (grepl("[\r\n]", value)) {
    .odb_abort(paste0(name, " must not contain line breaks."))
  }
  invisible(value)
}

.odb_postgres_settings <- function(
  host,
  dbname,
  issuer,
  scope,
  port,
  sslrootcert,
  connect_timeout,
  options
) {
  .odb_postgres_string(host, "host")
  if (
    grepl(",", host, fixed = TRUE) ||
      startsWith(host, "/") ||
      startsWith(host, "@") ||
      grepl("[[:space:]]|=", host)
  ) {
    .odb_abort("host must be one TCP hostname or address.")
  }
  .odb_postgres_string(dbname, "dbname")
  .odb_postgres_string(issuer, "issuer")
  if (
    !grepl("^https://[^/?#@[:space:]]+(/[^?#[:space:]]*)?$", issuer) ||
      grepl("/\\.well-known/", issuer)
  ) {
    .odb_abort(
      "issuer must be an HTTPS issuer identifier without a discovery suffix."
    )
  }
  .odb_postgres_string(scope, "scope")
  scopes <- strsplit(scope, " ", fixed = TRUE)[[1L]]
  if (
    startsWith(scope, " ") ||
      endsWith(scope, " ") ||
      !all(nzchar(scopes)) ||
      anyDuplicated(scopes) ||
      grepl("[\t\r\n]", scope)
  ) {
    .odb_abort("scope must contain distinct scopes separated by single spaces.")
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
  if (!is.null(sslrootcert)) {
    .odb_postgres_string(sslrootcert, "sslrootcert")
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
  .odb_named_args(options, "PostgreSQL options in ...")
  if (length(setdiff(names(options), allowed))) {
    .odb_abort(
      "Only RPostgres result, application_name and TCP keepalive options are accepted in ...; authentication, connection identity and TLS settings cannot be overridden."
    )
  }
  list(
    host = host,
    dbname = dbname,
    issuer = issuer,
    scope = scope,
    port = as.integer(port),
    sslrootcert = sslrootcert,
    connect_timeout = as.integer(connect_timeout),
    options = options
  )
}

.odb_postgres_runtime <- function() {
  if (!.Call(C_pg_bearer_available)) {
    return(.Call(C_pg_bearer_runtime, ""))
  }
  .odb_require("RPostgres")
  dll <- getLoadedDLLs()[["RPostgres"]]
  if (is.null(dll)) {
    .odb_abort("RPostgres's native library is not loaded.")
  }
  runtime <- .Call(C_pg_bearer_runtime, dll[["path"]])
  if (!isTRUE(runtime$default_hook)) {
    .odb_abort("Another libpq OAuth hook is installed; refusing to replace it.")
  }
  runtime
}

.odb_backend_postgres_oauth <- function(token, settings, user) {
  do.call(
    .odb_postgres_connect_bearer,
    c(list(token = token(), user = user()), settings)
  )
}

.odb_postgres_connection_valid <- function(connection) {
  isTRUE(DBI::dbIsValid(connection)) &&
    isTRUE(.Call(C_pg_connection_valid, connection))
}

.odb_postgres_connect_bearer <- function(
  token,
  user,
  host,
  dbname,
  issuer,
  scope,
  port = 5432L,
  sslrootcert = NULL,
  connect_timeout = 5L,
  options = list()
) {
  settings <- .odb_postgres_settings(
    host,
    dbname,
    issuer,
    scope,
    port,
    sslrootcert,
    connect_timeout,
    options
  )
  .odb_postgres_string(user, "user")
  .odb_string(token, "token")
  if (!grepl("^[A-Za-z0-9._~+/-]+=*$", token)) {
    .odb_abort("token must be a raw bearer token without whitespace.")
  }
  if (
    any(nzchar(Sys.getenv(c("PGSERVICE", "PGSERVICEFILE", "PGOAUTHDEBUG"))))
  ) {
    .odb_abort(
      "Unset PGSERVICE, PGSERVICEFILE and PGOAUTHDEBUG for native PostgreSQL OAuth."
    )
  }
  .odb_postgres_runtime()
  client_id <- "shinyOAuthDB-external-bearer-only"
  params <- c(
    list(
      host = host,
      dbname = dbname,
      user = user,
      port = as.character(settings$port),
      sslmode = "verify-full",
      sslrootcert = sslrootcert,
      connect_timeout = as.character(settings$connect_timeout),
      require_auth = "oauth",
      gssencmode = "disable",
      password = "shinyOAuthDB-password-disabled",
      passfile = "/dev/null",
      oauth_issuer = issuer,
      oauth_scope = scope,
      oauth_client_id = client_id
    ),
    options
  )
  open <- function() {
    do.call(DBI::dbConnect, c(list(RPostgres::Postgres()), params))
  }
  expected <- c(
    issuer,
    scope,
    host,
    as.character(settings$port),
    dbname,
    user,
    client_id
  )
  .Call(C_pg_with_bearer, token, expected, open)
}

#' Query Azure PostgreSQL as the signed-in user
#'
#' Read Azure Database for PostgreSQL data using each visitor's Microsoft
#' account. The database maps that account to a user or group role with
#' permission to query the data. The RPostgres connection works with DBI
#' or dbplyr.
#'
#' @inheritParams oauth_db_azure_sql
#' @param host PostgreSQL hostname.
#' @param dbname Database name.
#' @param user Database role created for the user or their group.
#' @param sslrootcert CA certificate bundle path, or `NULL` to use libpq's
#'   configured bundle.
#' @param ... RPostgres result options (`bigint`, `check_interrupts`,
#'   `timezone`, `timezone_out`), `connect_timeout`, `application_name`, or
#'   TCP keepalive options. Authentication and TLS options cannot be overridden.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install RPostgres linked to libpq 16 or later. Configure Azure PostgreSQL
#' for Entra authentication and create database roles for the users or their
#' groups. Use [oauth_db_microsoft_client()] with `services = "postgres"`.
#'
#' Create the helper inside `server()` and call `con()` before querying.
#' The connection uses verified TLS and sends the visitor's access token as
#' the password. The server must use that authentication method; Kerberos,
#' certificate-only and trust authentication aren't supported by this helper.
#' @examples
#' \dontrun{
#' con <- oauth_db_azure_postgres(
#'   auth$connection,
#'   host = "example.postgres.database.azure.com",
#'   dbname = "reporting",
#'   user = "reporting-readers",
#'   sslrootcert = "path/to/root-ca.pem"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user")
#' })
#' }
#' @seealso [oauth_db_microsoft_client()].
#'   `vignette("azure-postgres", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_azure_postgres <- function(
  authorization,
  host,
  dbname,
  user,
  ...,
  port = 5432L,
  sslrootcert = NULL,
  target = "postgres",
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("RPostgres")
  .odb_string(host, "host")
  .odb_string(dbname, "dbname")
  .odb_string(user, "user")
  options <- .odb_options(
    list(...),
    blocked = c(
      "host",
      "dbname",
      "port",
      "sslrootcert",
      "service",
      "passfile",
      "drv",
      "user",
      "password",
      "sslmode",
      "gssencmode",
      "require_auth"
    ),
    partial = "service"
  )
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
    .odb_abort(
      "Only RPostgres result, connection timeout, application_name and TCP keepalive options are accepted in ...; authentication and TLS settings cannot be overridden."
    )
  }
  .odb_bind(
    authorization,
    .odb_backend_postgres,
    host = host,
    dbname = dbname,
    user = user,
    port = port,
    sslrootcert = sslrootcert,
    options = options,
    target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_postgres <- function(
  token,
  host,
  dbname,
  user,
  port,
  sslrootcert,
  options
) {
  driver <- RPostgres::Postgres()
  if (DBI::dbGetInfo(driver)$client.version < package_version("16.0")) {
    .odb_abort(
      "Azure PostgreSQL OAuth requires RPostgres linked to libpq 16 or later to enforce token authentication. Update RPostgres or its libpq runtime.",
      "missing_dependency"
    )
  }
  args <- list(
    drv = driver,
    host = host,
    dbname = dbname,
    user = user,
    port = port,
    password = token(),
    sslmode = "verify-full",
    gssencmode = "disable",
    require_auth = "password"
  )
  if (!is.null(sslrootcert)) {
    args$sslrootcert <- sslrootcert
  }
  do.call(DBI::dbConnect, c(args, options))
}

.odb_postgres_profiles <- function(explicit_scopes = FALSE) {
  list(
    postgres = .odb_microsoft_profile(
      "postgres",
      "https://ossrdbms-aad.database.windows.net",
      if (explicit_scopes) "user_impersonation" else ".default"
    )
  )
}
