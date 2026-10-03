.odb_source_error <- function(message, reason = "invalid_configuration") {
  .odb_abort(message, reason)
}

.odb_source_string <- function(x, name, nullable = FALSE) {
  if (nullable && is.null(x)) {
    return(invisible(NULL))
  }
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    .odb_source_error(paste0(name, " must be one non-empty string."))
  }

  invisible(x)
}

.odb_source_host <- function(x, name = "server") {
  .odb_source_string(x, name)
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", x)) {
    .odb_source_error(paste0(
      name,
      " must be a hostname without a URL, port or connection string."
    ))
  }

  tolower(x)
}

.odb_source_origin <- function(x, name = "host") {
  .odb_source_string(x, name)
  if (!grepl("://", x, fixed = TRUE)) {
    x <- paste0("https://", x)
  }
  if (!grepl("^https://[A-Za-z0-9][A-Za-z0-9.-]*/?$", x)) {
    .odb_source_error(paste0(
      name,
      " must be an HTTPS origin without credentials, ports or paths."
    ))
  }

  sub("/$", "", tolower(x))
}

.odb_source_port <- function(x) {
  if (
    !is.numeric(x) ||
      length(x) != 1L ||
      is.na(x) ||
      x != as.integer(x) ||
      x < 1 ||
      x > 65535
  ) {
    .odb_source_error("port must be an integer between 1 and 65535.")
  }

  as.integer(x)
}

.odb_source_odbc_value <- function(value) {
  if (
    is.character(value) &&
      any(grepl("[;={}[:cntrl:]]|^[[:space:]]|[[:space:]]$", value))
  ) {
    .odb_source_error(
      "ODBC values cannot contain connection-string delimiters, control characters or outer whitespace. Supply separate source fields using ordinary names."
    )
  }

  invisible(value)
}

.odb_source_odbc_options <- function(options, allowed) {
  options <- .odb_source_options(options, allowed)
  for (value in options) {
    .odb_source_odbc_value(value)
  }

  options
}

.odb_source_bearer <- function(token) {
  .odb_source_string(token, "acquired access token")
  if (!grepl("^[A-Za-z0-9._~+/-]+=*$", token)) {
    .odb_source_error(
      "The acquired bearer credential contains invalid characters.",
      "invalid_credential"
    )
  }

  invisible(token)
}

.odb_source_options <- function(options, allowed) {
  # Native drivers accept many authentication knobs; expose only approved options.
  if (
    !is.list(options) ||
      (length(options) &&
        (is.null(names(options)) ||
          anyNA(names(options)) ||
          any(!nzchar(names(options))) ||
          anyDuplicated(tolower(names(options))) ||
          !all(names(options) %in% allowed)))
  ) {
    .odb_source_error(paste0(
      "options must be a named list selecting: ",
      paste(allowed, collapse = ", "),
      ". Credentials, endpoints and alternate authentication cannot be overridden."
    ))
  }
  if (
    any(vapply(
      options,
      function(x) !is.atomic(x) || length(x) != 1L || is.na(x),
      logical(1)
    ))
  ) {
    .odb_source_error(
      "Each connection option must be one non-missing atomic value."
    )
  }

  options
}

.odb_source_scopes <- function(scopes, resource, required_scopes = scopes) {
  for (value in list(scopes, required_scopes)) {
    if (
      !is.character(value) ||
        anyNA(value) ||
        any(!nzchar(value)) ||
        any(grepl("[[:space:]?#]", value))
    ) {
      .odb_source_error(
        "scopes and required_scopes must be character vectors of OAuth scopes."
      )
    }
  }
  if (
    length(scopes) &&
      !is.null(resource) &&
      !all(startsWith(scopes, paste0(resource, "/")))
  ) {
    .odb_source_error(
      "Every scope must be fully qualified with this source's exact resource."
    )
  }
  if (
    !all(required_scopes %in% scopes) ||
      any(endsWith(required_scopes, "/.default"))
  ) {
    .odb_source_error(
      "required_scopes must select explicit permissions from scopes; .default is a consent profile."
    )
  }

  list(scopes = unique(scopes), required_scopes = unique(required_scopes))
}

.odb_source_custom_config <- function(value, depth = 0L) {
  if (
    depth >= 50L ||
      is.environment(value) ||
      is.function(value) ||
      isS4(value) ||
      typeof(value) %in%
        c("externalptr", "weakref", "symbol", "language", "pairlist")
  ) {
    .odb_source_error(
      "Custom configuration and bindings must contain plain non-secret data, without functions, environments or live objects."
    )
  }
  if (is.list(value)) {
    key <- tolower(gsub("[._ -]", "", names(value)))
    forbidden <- c(
      "password",
      "pwd",
      "token",
      "tokens",
      "accesstoken",
      "refreshtoken",
      "idtoken",
      "clientsecret",
      "secret",
      "clientassertion",
      "privatekey",
      "privatekeyfile",
      "privatekeypath",
      "tokenfilepath",
      "connectionstring",
      "connstr",
      "authorization",
      "bearer",
      "apikey",
      "awsaccesskeyid",
      "awssecretaccesskey",
      "awssessiontoken"
    )

    if (any(key %in% forbidden)) {
      .odb_source_error(
        "Custom configuration and bindings cannot contain credentials or connection strings. Obtain credentials through the supplied token provider."
      )
    }
    for (element in value) {
      .odb_source_custom_config(element, depth + 1L)
    }
  }

  # Inspect attributes too: classed values can carry hidden live state or secrets.
  attrs <- attributes(value)
  if (!is.null(attrs)) {
    for (attribute in attrs) {
      .odb_source_custom_config(attribute, depth + 1L)
    }
  }

  invisible(value)
}
