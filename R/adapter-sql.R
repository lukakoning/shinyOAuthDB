.odb_odbc_connect <- function(source, token_provider) {
  .odb_require("odbc", "Microsoft SQL Server connections", version = "1.3.4")
  config <- source$config
  token <- token_provider(force_refresh = FALSE, async = FALSE)
  .odb_source_bearer(token)
  args <- list(drv = odbc::odbc(), driver = config$driver,
    server = paste0(config$server, ",", config$port), database = config$database,
    Encrypt = "yes", TrustServerCertificate = "no",
    attributes = list(azure_token = token))
  do.call(DBI::dbConnect, c(args, config$options))
}

.odb_postgres_connect <- function(source, token_provider) {
  .odb_require("RPostgres", "Azure PostgreSQL connections")
  config <- source$config
  token <- token_provider(force_refresh = FALSE, async = FALSE)
  .odb_source_bearer(token)
  args <- list(drv = RPostgres::Postgres(), host = config$host, dbname = config$database,
    port = config$port, user = config$user, password = token, sslmode = "verify-full")
  if (!is.null(config$sslrootcert)) args$sslrootcert <- config$sslrootcert
  do.call(DBI::dbConnect, c(args, config$options))
}

.odb_snowflake_connect <- function(source, token_provider) {
  .odb_require("odbc", "Snowflake OAuth connections")
  config <- source$config
  token <- token_provider(force_refresh = FALSE, async = FALSE)
  .odb_source_bearer(token)
  args <- list(drv = odbc::odbc(), driver = config$driver, server = config$server,
    database = config$database, schema = config$schema, warehouse = config$warehouse,
    role = config$role, authenticator = "oauth", token = token)
  do.call(DBI::dbConnect, c(args, config$options))
}
