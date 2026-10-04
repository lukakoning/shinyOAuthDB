#' Use the user's authorization with Azure PostgreSQL
#'
#' Uses RPostgres with the user's Entra token as the password. The provisioned
#' database role and server permissions must already exist. The default
#' `.default` scope is a consent request, not a literal token permission.
#' @inheritParams oauth_db_azure_sql
#' @param host PostgreSQL hostname.
#' @param user Provisioned individual or group database role.
#' @param sslrootcert CA bundle path, or `NULL` for libpq's configured CA bundle.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_azure_postgres <- function(
  authorization, host, database, user, ..., port = 5432L, sslrootcert = NULL,
  target = "postgres", scopes = "https://ossrdbms-aad.database.windows.net/.default",
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("RPostgres")
  .odb_string(host, "host")
  .odb_string(database, "database")
  .odb_string(user, "user")
  options <- .odb_options(list(...), blocked = c(
    "host", "dbname", "port", "sslrootcert", "service", "passfile", "drv",
    "user", "password", "sslmode"))
  .odb_bind(authorization, .odb_backend_postgres, host = host, database = database,
    user = user, port = port, sslrootcert = sslrootcert, options = options,
    target = target, scopes = .odb_microsoft_scopes(scopes), min_valid_for = min_valid_for, session = session)
}

.odb_backend_postgres <- function(token, host, database, user, port, sslrootcert, options) {
  args <- list(drv = RPostgres::Postgres(), host = host, dbname = database,
    user = user, port = port, password = token(), sslmode = "verify-full")
  if (!is.null(sslrootcert)) args$sslrootcert <- sslrootcert
  do.call(DBI::dbConnect, c(args, options))
}

.odb_postgres_profiles <- function() {
  list(postgres = .odb_microsoft_profile("postgres", "https://ossrdbms-aad.database.windows.net", ".default"))
}
