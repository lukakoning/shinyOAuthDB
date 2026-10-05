#' Use the user's authorization with Azure PostgreSQL
#'
#' Uses RPostgres with the user's Entra token as the password. The provisioned
#' database role and server permissions must already exist. Configure `.default`
#' consent on the shinyOAuth client; it is not a literal token permission.
#' @inheritParams oauth_db_azure_sql
#' @param host PostgreSQL hostname.
#' @param dbname Database name, passed to RPostgres unchanged.
#' @param required_scopes Required granted permissions, empty by default. Supply
#'   actual permission scopes if your deployment requires an additional check.
#' @param user Provisioned individual or group database role.
#' @param sslrootcert CA bundle path, or `NULL` for libpq's configured CA bundle.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @seealso [oauth_db_microsoft_client()]
#' @examples
#' \dontrun{
#' # Inside server(); configure the Microsoft client with services = "postgres".
#' con <- oauth_db_azure_postgres(auth$connection,
#'   host = "example.postgres.database.azure.com", dbname = "sales",
#'   user = "reporting-readers", sslrootcert = "path/to/root-ca.pem")
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT current_user AS database_user")
#' })
#' }
#' @export
oauth_db_azure_postgres <- function(
  authorization, host, dbname, user, ..., port = 5432L, sslrootcert = NULL,
  target = "postgres", required_scopes = character(),
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("RPostgres")
  .odb_string(host, "host")
  .odb_string(dbname, "dbname")
  .odb_string(user, "user")
  options <- .odb_options(list(...), blocked = c(
    "host", "dbname", "port", "sslrootcert", "service", "passfile", "drv",
    "user", "password", "sslmode"))
  .odb_bind(authorization, .odb_backend_postgres, host = host, dbname = dbname,
    user = user, port = port, sslrootcert = sslrootcert, options = options,
    target = target, required_scopes = .odb_microsoft_scopes(required_scopes), min_valid_for = min_valid_for, session = session)
}

.odb_backend_postgres <- function(token, host, dbname, user, port, sslrootcert, options) {
  args <- list(drv = RPostgres::Postgres(), host = host, dbname = dbname,
    user = user, port = port, password = token(), sslmode = "verify-full")
  if (!is.null(sslrootcert)) args$sslrootcert <- sslrootcert
  do.call(DBI::dbConnect, c(args, options))
}

.odb_postgres_profiles <- function() {
  list(postgres = .odb_microsoft_profile("postgres", "https://ossrdbms-aad.database.windows.net", ".default"))
}
