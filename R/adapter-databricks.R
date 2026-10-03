.odb_databricks_token_provider <- function(source, credential_fun) {
  .odb_require("brickster", "Databricks credential providers")
  if (!"db_token_provider" %in% getNamespaceExports("brickster")) {
    .odb_abort("Install brickster with the public db_token_provider() API for delegated user credentials.", "unsupported_dependency")
  }
  brickster::db_token_provider(source$config$host,
    function(force_refresh = FALSE) credential_fun(force_refresh = force_refresh, async = FALSE))
}

.odb_databricks_connect <- function(source, token_provider) {
  .odb_require("brickster", "Databricks SQL connections")
  if (is.null(source$config$warehouse_id)) {
    .odb_abort("Configure warehouse_id to request a native Databricks SQL connection.", "unsupported_operation")
  }
  config <- source$config
  args <- config[c("host", "warehouse_id", "catalog", "schema")]
  args <- args[!vapply(args, is.null, logical(1))]
  args$drv <- brickster::DatabricksSQL()
  args$token <- token_provider
  do.call(DBI::dbConnect, c(args, config$options))
}
