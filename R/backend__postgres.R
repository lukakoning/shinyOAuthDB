#' Query Azure PostgreSQL as the signed-in user
#'
#' Query Azure Database for PostgreSQL with a visitor's Microsoft account.
#' The connection works with DBI or dbplyr through RPostgres.
#'
#' @inheritParams oauth_db_azure_sql
#' @param host PostgreSQL hostname.
#' @param dbname Database name.
#' @param user Database role created for the user or their group.
#' @param sslrootcert CA certificate bundle path, or `NULL` to use libpq's
#'   configured bundle.
#' @param ... RPostgres connection options, such as `connect_timeout`.
#' @return A reactive function returning an RPostgres DBI connection.
#' @details
#' Install RPostgres and use [oauth_db_microsoft_client()] with
#' `services = "postgres"`. The server must accept Entra authentication,
#' and the database role must already exist.
#'
#' Create the helper inside `server()` and get `connection <- con()`
#' inside a render or reactive expression before querying.
#' The connection uses verified TLS.
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
#' @family database connections
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
