#' Query Azure SQL as the signed-in user
#'
#' Create a DBI connection for queries with DBI or dbplyr. Use this for Azure
#' SQL Database, SQL Managed Instance, or a compatible Synapse SQL endpoint.
#' The database must be configured to accept Microsoft Entra authentication.
#'
#' @inheritParams oauth_db_connect
#' @param server Database hostname.
#' @param database Database name.
#' @param driver Installed ODBC driver name.
#' @param port Database port.
#' @param ... Additional named odbc connection options, such as `timeout`.
#'   The helper supplies authentication and verified TLS settings.
#' @return A reactive function returning a DBI connection. Create `con` in
#'   `server()`, then call `connection <- con()` before each database operation.
#' @details
#' Install odbc and Microsoft ODBC Driver 18 for SQL Server. Configure the
#' Microsoft sign-in client with `services = "sql"`, or use an existing client
#' with the appropriate token target.
#'
#' Connections open on first use and close on sign-out or session end. For
#' server or database names containing ODBC delimiters, use [odbc::quote_value()].
#' @examples
#' \dontrun{
#' # Inside server():
#' con <- oauth_db_azure_sql(
#'   auth$connection,
#'   server = "example.database.windows.net",
#'   database = "Reporting"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT TOP (20) name FROM sys.tables")
#' })
#' }
#' @seealso [oauth_db_microsoft_client()], [oauth_db_sql_server()]
#' @family database connections
#' @export
oauth_db_azure_sql <- function(
  authorization, server, database, ...,
  target = "sql", required_scopes = character(),
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  if (length(port) != 1L || is.na(port) || !grepl("^[0-9]+$", port) ||
      as.numeric(port) < 1 || as.numeric(port) > 65535) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  .odb_odbc_values(list(server, database, driver, port))
  options <- .odb_options(list(...), blocked = c(
    "server", "database", "driver", "port", "drv", "dsn", ".connection_string",
    "connection_string", "attributes", "token", "access_token", "user", "uid",
    "pwd", "password", "authentication", "authenticator", "trusted_connection",
    "integrated_security", "encrypt", "trust_server_certificate"))
  .odb_odbc_values(options)
  .odb_bind(authorization, .odb_backend_sql, server = server, database = database,
    driver = driver, port = port, options = options, target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes), min_valid_for = min_valid_for, session = session)
}

#' Query an Entra-enabled SQL Server as the signed-in user
#'
#' Use this for SQL Server deployments configured to accept Microsoft Entra
#' access tokens. It uses the same connection settings as [oauth_db_azure_sql()].
#'
#' @inheritParams oauth_db_azure_sql
#' @return A reactive function returning a DBI connection.
#' @family database connections
#' @export
oauth_db_sql_server <- oauth_db_azure_sql

.odb_backend_sql <- function(token, server, database, driver, port, options) {
  address <- paste0(server, ",", port)
  if (is.character(server) && length(server) == 1L && .odb_odbc_quoted(server)) {
    quote <- substr(server, 1L, 1L)
    address <- I(paste0(quote, substr(server, 2L, nchar(server) - 1L), ",", port, quote))
  }
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver,
    server = address, database = database, Encrypt = "yes",
    TrustServerCertificate = "no", attributes = list(azure_token = token())), options))
}

.odb_sql_server_profiles <- function() {
  list(sql = .odb_microsoft_profile("sql", "https://database.windows.net/", "user_impersonation"))
}
