#' Query Azure SQL as the signed-in user
#'
#' Read Azure SQL data in a Shiny app using each visitor's Microsoft account
#' and database permissions. The helper provides a DBI connection for SQL
#' or dbplyr queries. It also works with SQL Managed Instance and compatible
#' Synapse SQL endpoints.
#'
#' @inheritParams oauth_db_connect
#' @param server Database hostname.
#' @param database Database name.
#' @param driver Installed ODBC driver name.
#' @param port Database port.
#' @param ... Named odbc connection options, such as `timeout`.
#'   The helper sets authentication and verified TLS.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and Microsoft ODBC Driver 18 for SQL Server. Configure the
#' database for Microsoft Entra sign-in and give users access to the data.
#' Use [oauth_db_microsoft_client()] with `services = "sql"` for sign-in.
#'
#' Create the helper inside `server()` and call `con()` before querying.
#' The connection opens on first use and closes when the authorization or
#' Shiny session ends. See [oauth_db_connect()] for shared session behavior.
#'
#' For connection names containing ODBC delimiters, use [odbc::quote_value()].
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
#' @seealso [oauth_db_microsoft_client()], [oauth_db_sql_server()].
#'   `vignette("azure-sql", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_azure_sql <- function(
  authorization,
  server,
  database,
  ...,
  target = "sql",
  required_scopes = character(),
  driver = "ODBC Driver 18 for SQL Server",
  port = 1433L,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  .odb_string(database, "database")
  .odb_string(driver, "driver")
  if (
    length(port) != 1L ||
      is.na(port) ||
      !grepl("^[0-9]+$", port) ||
      as.numeric(port) < 1 ||
      as.numeric(port) > 65535
  ) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  .odb_odbc_values(list(server, database, driver, port))
  options <- .odb_options(
    list(...),
    blocked = c(
      "server",
      "addr",
      "address",
      "database",
      "driver",
      "port",
      "drv",
      "dsn",
      "filedsn",
      "savefile",
      "failover_partner",
      ".connection_string",
      "connection_string",
      "attributes",
      "token",
      "access_token",
      "user",
      "uid",
      "pwd",
      "password",
      "authentication",
      "authenticator",
      "trusted_connection",
      "integrated_security",
      "encrypt",
      "trust_server_certificate"
    ),
    partial = "dsn"
  )
  .odb_odbc_values(options)
  .odb_bind(
    authorization,
    .odb_backend_sql,
    server = server,
    database = database,
    driver = driver,
    port = port,
    options = options,
    target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes),
    min_valid_for = min_valid_for,
    session = session
  )
}

#' Query SQL Server as the signed-in user
#'
#' Read SQL Server data in a Shiny app with each visitor's Microsoft account.
#' The server must accept Microsoft Entra tokens. This is the same connection
#' helper as [oauth_db_azure_sql()], with the same arguments.
#'
#' @inheritParams oauth_db_azure_sql
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and Microsoft ODBC Driver 18 for SQL Server. Use
#' [oauth_db_microsoft_client()] with `services = "sql"` for sign-in.
#' Create the helper inside `server()` and call `con()` before querying.
#' See [oauth_db_azure_sql()] for connection requirements and options.
#' @seealso [oauth_db_azure_sql()], [oauth_db_microsoft_client()].
#'   `vignette("azure-sql", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_sql_server <- oauth_db_azure_sql

.odb_backend_sql <- function(token, server, database, driver, port, options) {
  address <- paste0(server, ",", port)
  if (
    is.character(server) && length(server) == 1L && .odb_odbc_quoted(server)
  ) {
    quote <- substr(server, 1L, 1L)
    address <- I(paste0(
      quote,
      substr(server, 2L, nchar(server) - 1L),
      ",",
      port,
      quote
    ))
  }
  .odb_odbc_connect(
    c(
      list(
        drv = odbc::odbc(),
        driver = driver,
        server = address,
        database = database,
        Encrypt = "yes",
        TrustServerCertificate = "no",
        attributes = list(azure_token = token())
      ),
      options
    )
  )
}

.odb_sql_server_profiles <- function() {
  list(
    sql = .odb_microsoft_profile(
      "sql",
      "https://database.windows.net/",
      "user_impersonation"
    )
  )
}
