.odb_source_identity <- function(value) {
  if (is.function(value)) {
    # Never serialize a hook's closure: it may capture app/session credentials.
    return(list(
      formals = deparse(formals(value)),
      body = deparse(body(value)),
      environment = format(environment(value))
    ))
  }
  if (is.list(value)) {
    return(lapply(value, .odb_source_identity))
  }

  value
}

.odb_new_source <- function(
  backend,
  config,
  provider_family,
  target,
  resource,
  scopes,
  required_scopes = scopes,
  capabilities = list(),
  protected_args = character(),
  adapter = NULL
) {
  .odb_source_string(backend, "backend")
  .odb_source_string(provider_family, "provider_family")
  .odb_source_string(target, "target", nullable = TRUE)
  .odb_source_string(resource, "resource", nullable = TRUE)

  profile <- .odb_source_scopes(scopes, resource, required_scopes)
  auth <- c(
    list(
      provider_family = provider_family,
      target = target,
      resource = resource
    ),
    profile
  )
  value <- list(
    backend = backend,
    config = config,
    auth = auth,
    capabilities = capabilities,
    protected_args = unique(protected_args)
  )
  if (!is.null(adapter)) {
    value$adapter <- adapter
  }

  # The fingerprint covers configuration, not credentials held by hook closures.
  value$id <- paste0(
    backend,
    ":",
    digest::digest(.odb_source_identity(value), algo = "sha256")
  )

  structure(
    value[c("id", setdiff(names(value), "id"))],
    class = "oauth_db_source"
  )
}

.odb_validate_source <- function(source) {
  if (
    !inherits(source, "oauth_db_source") ||
      !is.list(source) ||
      !all(
        c(
          "id",
          "backend",
          "config",
          "auth",
          "capabilities",
          "protected_args"
        ) %in%
          names(source)
      )
  ) {
    .odb_source_error("source must be an oauth_db_source constructor result.")
  }

  invisible(source)
}

#' Describe a custom delegated database adapter
#'
#' Supply trusted application connectors rather than introducing another query
#' engine. A connector receives `config` and `token_provider`; it must use only
#' the supplied credential and return a native DBI connection. Closures are for
#' synchronous use; background work requires portable namespace functions.
#' Portable descriptors have deterministic IDs. A closure-backed custom source
#' uses the hook's process-local environment identity without serializing its
#' captured values; its ID need not persist across R processes.
#' @param backend Adapter name.
#' @param connect Function accepting `config` and `token_provider`, or portable
#'   native specification `list(package, fun, driver = list(package, fun),
#'   credential_arg = "password")`. `credential_arg` receives the supplied
#'   scalar user token. Without it the specification is a credential-free
#'   transport, useful for offline fixtures, and does not claim delegated access.
#' @param disconnect Function accepting the native connection.
#' @param token_provider Optional function accepting `source` and
#'   `credential_fun`, adapting it to a native credential provider.
#' @param config Non-secret connector configuration.
#' @param target,resource,scopes,required_scopes,provider_family OAuth profile.
#' @param capabilities Adapter capability overrides.
#' @param bindings Additional protected connector configuration for tasks.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_custom <- function(
  backend,
  connect,
  disconnect = DBI::dbDisconnect,
  token_provider = NULL,
  config = list(),
  target = NULL,
  resource = NULL,
  scopes = character(),
  required_scopes = scopes,
  provider_family = "custom",
  capabilities = list(),
  bindings = list()
) {
  if (
    (!is.function(connect) && !is.list(connect)) ||
      !is.function(disconnect) ||
      (!is.null(token_provider) && !is.function(token_provider))
  ) {
    .odb_source_error(
      "Custom connect/disconnect/token_provider hooks must be functions."
    )
  }
  if (
    is.function(connect) &&
      !all(c("config", "token_provider") %in% names(formals(connect)))
  ) {
    .odb_source_error(
      "Custom connect must accept config and token_provider arguments explicitly."
    )
  }
  if (!is.list(config) || !is.list(capabilities) || !is.list(bindings)) {
    .odb_source_error("config, capabilities and bindings must be lists.")
  }

  .odb_source_custom_config(config)
  .odb_source_custom_config(bindings)
  caps <- utils::modifyList(.odb_sql_capabilities("custom"), capabilities)
  if (is.list(connect)) {
    for (spec in list(connect, connect$driver)) {
      if (!is.list(spec)) {
        .odb_source_error(
          "A portable connector needs package, fun and a driver specification."
        )
      }

      .odb_source_string(spec$package, "connector package")
      .odb_source_string(spec$fun, "connector function")
    }

    .odb_source_string(
      connect$credential_arg,
      "credential_arg",
      nullable = TRUE
    )
    if (
      !is.null(connect$credential_arg) &&
        connect$credential_arg %in% names(config)
    ) {
      .odb_source_error(
        "Portable credential_arg is supplied by the broker and cannot also appear in config."
      )
    }
    if (
      !is.null(connect$credential_arg) &&
        connect$credential_arg %in%
          c("drv", "driver", "host", "server", "port", "database", "dbname")
    ) {
      .odb_source_error(
        "credential_arg must name the native connector's credential argument, not a driver or endpoint argument."
      )
    }

    caps$delegated_user <- !is.null(connect$credential_arg)
    caps$credential_transport <- if (caps$delegated_user) {
      "explicit_scalar_credential"
    } else {
      "credential_free_fixture"
    }
  }
  if (identical(disconnect, DBI::dbDisconnect)) {
    disconnect <- list(package = "DBI", fun = "dbDisconnect")
  }

  .odb_new_source(
    backend,
    config,
    provider_family,
    target,
    resource,
    scopes,
    required_scopes,
    caps,
    c(.odb_sql_protected, names(bindings)),
    list(
      connect = connect,
      disconnect = disconnect,
      token_provider = token_provider,
      bindings = bindings
    )
  )
}

#' Inspect a source's backend capabilities
#' @param source An `oauth_db_source` descriptor.
#' @returns A list of declared capabilities, installation status and limitations.
#'   Availability does not prove live database access.
#' @export
oauth_db_capabilities <- function(source) {
  .odb_validate_source(source)

  package <- source$capabilities$connector_package
  installed <- identical(package, "custom") ||
    requireNamespace(package, quietly = TRUE)

  c(
    source$capabilities,
    list(
      dependency_installed = installed,
      source_id = source$id,
      target = source$auth$target
    )
  )
}

#' @export
print.oauth_db_source <- function(x, ...) {
  cat("<oauth_db_source:", x$backend, ">\n", sep = "")
  cat(
    "  Target:",
    x$auth$target,
    "\n  Native DBI:",
    isTRUE(x$capabilities$native_dbi),
    "\n"
  )

  invisible(x)
}
