.odb_operation_export <- function(fun) {
  if (!is.function(fun)) {
    .odb_abort(
      "operation must be an existing supported package function, for example DBI::dbGetQuery or brickster::db_sql_query."
    )
  }

  registry <- list(
    DBI = c(
      "dbGetQuery",
      "dbExecute",
      "dbReadTable",
      "dbListTables",
      "dbListFields"
    ),
    brickster = c("db_sql_query", "db_sql_exec_query", "db_sql_warehouse_list"),
    fabricQueryR = c(
      "fabric_workspaces",
      "fabric_items",
      "fabric_sql_query",
      "fabric_kql_query",
      "fabric_pbi_dax_query",
      "fabric_graphql_query",
      "fabric_onelake_list",
      "fabric_onelake_read_file",
      "fabric_onelake_read_delta_table"
    )
  )

  # Resolve by function identity so workers receive an export name, not a closure.
  for (candidate_package in names(registry)) {
    if (!requireNamespace(candidate_package, quietly = TRUE)) {
      next
    }
    exports <- getNamespaceExports(candidate_package)
    for (candidate_name in registry[[candidate_package]]) {
      if (
        candidate_name %in%
          exports &&
          identical(fun, getExportedValue(candidate_package, candidate_name))
      ) {
        return(list(package = candidate_package, fun = candidate_name))
      }
    }
  }

  .odb_abort(
    "This function has no adapter operation mapping. Use a supported exported DBI, brickster or fabricQueryR function; arbitrary closures cannot run as delegated tasks.",
    "unsupported_operation"
  )
}

.odb_operation_spec <- function(source, fun) {
  .odb_validate_source(source)
  operation <- .odb_operation_export(fun)
  package <- operation$package
  name <- operation$fun

  # Bind trusted source fields before accepting per-invocation arguments.
  bindings <- list()
  credential_arg <- "token"
  connection_arg <- NULL
  if (package == "DBI") {
    if (!isTRUE(source$capabilities$native_dbi)) {
      .odb_abort(
        "This source does not support DBI operations.",
        "unsupported_operation"
      )
    }

    credential_arg <- connection_arg <- "conn"
  } else if (package == "brickster") {
    if (source$backend != "databricks") {
      .odb_abort(
        "brickster operations need a Databricks source.",
        "unsupported_operation"
      )
    }

    config <- c(source$config, source$config$options)
    selected <- intersect(
      c(
        "host",
        "warehouse_id",
        "catalog",
        "schema",
        names(source$config$options)
      ),
      names(formals(fun))
    )
    bindings <- config[selected]
    bindings <- bindings[!vapply(bindings, is.null, logical(1))]
    if (name != "db_sql_warehouse_list" && is.null(bindings$warehouse_id)) {
      .odb_abort(
        "This brickster SQL operation needs a configured warehouse_id.",
        "unsupported_operation"
      )
    }
  } else {
    services <- c(
      fabric_workspaces = "fabric",
      fabric_items = "fabric",
      fabric_sql_query = "sql",
      fabric_kql_query = "kql",
      fabric_pbi_dax_query = "dax",
      fabric_graphql_query = "graphql",
      fabric_onelake_list = "onelake",
      fabric_onelake_read_file = "onelake",
      fabric_onelake_read_delta_table = "onelake"
    )

    if (
      !source$backend %in% c("fabric", "fabric_sql") ||
        source$config$service != services[[name]]
    ) {
      .odb_abort(
        "The native Fabric operation needs a source for its specific service.",
        "unsupported_operation"
      )
    }

    bindings <- .odb_fabric_operation_bindings(source, name)
  }

  list(
    package = package,
    fun = name,
    credential_arg = credential_arg,
    connection_arg = connection_arg,
    bindings = bindings,
    required_scopes = source$auth$required_scopes,
    protected_args = unique(c(
      source$protected_args,
      credential_arg,
      names(bindings)
    )),
    effect = "unknown"
  )
}
