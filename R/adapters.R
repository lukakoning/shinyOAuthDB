.odb_adapter_token_provider <- function(source, credential_fun) {
  .odb_validate_source(source)
  if (!is.function(credential_fun)) .odb_abort("credential_fun must be a function.")
  if (!is.null(source$adapter$token_provider)) {
    return(source$adapter$token_provider(source, credential_fun))
  }
  switch(source$backend,
    fabric = .odb_fabric_token_provider(source, credential_fun),
    fabric_sql = .odb_fabric_token_provider(source, credential_fun),
    databricks = .odb_databricks_token_provider(source, credential_fun),
    credential_fun)
}

.odb_adapter_connect <- function(source, token_provider) {
  .odb_validate_source(source)
  if (!isTRUE(source$capabilities$native_dbi)) {
    .odb_abort("This source does not supply native DBI connections. Use its token_provider() with the existing service package.", "unsupported_operation")
  }
  if (!is.null(source$adapter$connect)) {
    connector <- source$adapter$connect
    if (is.function(connector)) return(connector(config = source$config, token_provider = token_provider))
    .odb_require(connector$package, "custom native database connector")
    .odb_require(connector$driver$package, "custom native database driver")
    driver <- getExportedValue(connector$driver$package, connector$driver$fun)()
    args <- c(list(drv = driver), source$config)
    if (!is.null(connector$credential_arg)) {
      token <- token_provider(force_refresh = FALSE, async = FALSE)
      .odb_source_bearer(token)
      args[[connector$credential_arg]] <- token
    }
    return(do.call(getExportedValue(connector$package, connector$fun), args))
  }
  switch(source$backend,
    azure_sql = .odb_odbc_connect(source, token_provider),
    sql_server = .odb_odbc_connect(source, token_provider),
    azure_postgres = .odb_postgres_connect(source, token_provider),
    fabric_sql = .odb_fabric_connect(source, token_provider),
    databricks = .odb_databricks_connect(source, token_provider),
    snowflake = .odb_snowflake_connect(source, token_provider),
    .odb_abort("This source has no installed native connection adapter.", "unsupported_operation"))
}

.odb_adapter_disconnect <- function(source, native) {
  .odb_validate_source(source)
  hook <- source$adapter$disconnect
  if (is.function(hook)) return(hook(native))
  if (is.list(hook)) return(getExportedValue(hook$package, hook$fun)(native))
  DBI::dbDisconnect(native)
}

.odb_operation_spec <- function(source, fun) {
  .odb_validate_source(source)
  if (!is.function(fun)) {
    .odb_abort("operation must be an existing supported package function, for example DBI::dbGetQuery or brickster::db_sql_query.")
  }
  registry <- list(
    DBI = c("dbGetQuery", "dbExecute", "dbReadTable", "dbListTables", "dbListFields"),
    brickster = c("db_sql_query", "db_sql_exec_query", "db_sql_warehouse_list"),
    fabricQueryR = c("fabric_workspaces", "fabric_items", "fabric_sql_query", "fabric_kql_query",
      "fabric_pbi_dax_query", "fabric_graphql_query", "fabric_onelake_list",
      "fabric_onelake_read_file", "fabric_onelake_read_delta_table"))
  package <- name <- NULL
  for (candidate_package in names(registry)) {
    if (!requireNamespace(candidate_package, quietly = TRUE)) next
    for (candidate_name in registry[[candidate_package]]) {
      if (candidate_name %in% getNamespaceExports(candidate_package) &&
          identical(fun, getExportedValue(candidate_package, candidate_name))) {
        package <- candidate_package
        name <- candidate_name
        break
      }
    }
    if (!is.null(package)) break
  }
  if (is.null(package)) {
    .odb_abort("This function has no adapter operation mapping. Use a supported exported DBI, brickster or fabricQueryR function; arbitrary closures cannot run as delegated tasks.", "unsupported_operation")
  }
  bindings <- list()
  credential_arg <- "token"
  connection_arg <- NULL
  if (package == "DBI") {
    if (!isTRUE(source$capabilities$native_dbi)) .odb_abort("This source does not support DBI operations.", "unsupported_operation")
    credential_arg <- connection_arg <- "conn"
  } else if (package == "brickster") {
    if (source$backend != "databricks") .odb_abort("brickster operations need a Databricks source.", "unsupported_operation")
    config <- c(source$config, source$config$options)
    selected <- intersect(c("host", "warehouse_id", "catalog", "schema", names(source$config$options)), names(formals(fun)))
    bindings <- config[selected]
    bindings <- bindings[!vapply(bindings, is.null, logical(1))]
    if (name != "db_sql_warehouse_list" && is.null(bindings$warehouse_id)) {
      .odb_abort("This brickster SQL operation needs a configured warehouse_id.", "unsupported_operation")
    }
  } else {
    services <- c(fabric_workspaces = "fabric", fabric_items = "fabric", fabric_sql_query = "sql",
      fabric_kql_query = "kql", fabric_pbi_dax_query = "dax", fabric_graphql_query = "graphql",
      fabric_onelake_list = "onelake", fabric_onelake_read_file = "onelake",
      fabric_onelake_read_delta_table = "onelake")
    if (!source$backend %in% c("fabric", "fabric_sql") || source$config$service != services[[name]]) {
      .odb_abort("The native Fabric operation needs a source for its specific service.", "unsupported_operation")
    }
    bindings <- .odb_fabric_operation_bindings(source, name)
  }
  list(package = package, fun = name, credential_arg = credential_arg,
       connection_arg = connection_arg, bindings = bindings,
       required_scopes = source$auth$required_scopes,
       protected_args = unique(c(source$protected_args, credential_arg, names(bindings))),
       effect = "unknown")
}
