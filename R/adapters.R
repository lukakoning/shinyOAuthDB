.odb_adapter_token_provider <- function(source, credential_fun) {
  .odb_validate_source(source)
  if (!is.function(credential_fun)) {
    .odb_abort("credential_fun must be a function.")
  }
  if (!is.null(source$adapter$token_provider)) {
    return(source$adapter$token_provider(source, credential_fun))
  }

  switch(
    source$backend,
    fabric = .odb_fabric_token_provider(source, credential_fun),
    fabric_sql = .odb_fabric_token_provider(source, credential_fun),
    databricks = .odb_databricks_token_provider(source, credential_fun),
    credential_fun
  )
}

.odb_adapter_connect <- function(source, token_provider) {
  .odb_validate_source(source)
  if (!isTRUE(source$capabilities$native_dbi)) {
    .odb_abort(
      "This source does not supply native DBI connections. Use its token_provider() with the existing service package.",
      "unsupported_operation"
    )
  }
  if (!is.null(source$adapter$connect)) {
    connector <- source$adapter$connect
    if (is.function(connector)) {
      return(connector(config = source$config, token_provider = token_provider))
    }

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

  switch(
    source$backend,
    azure_sql = .odb_odbc_connect(source, token_provider),
    sql_server = .odb_odbc_connect(source, token_provider),
    azure_postgres = .odb_postgres_connect(source, token_provider),
    fabric_sql = .odb_fabric_connect(source, token_provider),
    databricks = .odb_databricks_connect(source, token_provider),
    snowflake = .odb_snowflake_connect(source, token_provider),
    .odb_abort(
      "This source has no installed native connection adapter.",
      "unsupported_operation"
    )
  )
}

.odb_adapter_disconnect <- function(source, native) {
  .odb_validate_source(source)

  hook <- source$adapter$disconnect
  if (is.function(hook)) {
    return(hook(native))
  }
  if (is.list(hook)) {
    return(getExportedValue(hook$package, hook$fun)(native))
  }

  DBI::dbDisconnect(native)
}
