.odb_http_url <- function(url) {
  .odb_string(url, "url")
  address <- tryCatch(httr2::url_parse(url), error = function(e) NULL)
  if (
    is.null(address) ||
      !identical(tolower(address$scheme), "https") ||
      is.null(address$hostname) ||
      !nzchar(address$hostname) ||
      !is.null(address$username) ||
      !is.null(address$password) ||
      !is.null(address$query) ||
      !is.null(address$fragment) ||
      grepl("[[:space:]\\\\]", url) ||
      any(
        strsplit(utils::URLdecode(url), "/", fixed = TRUE)[[1L]] %in%
          c(".", "..")
      )
  ) {
    .odb_abort(
      "url must be an HTTPS address without credentials, a query, fragment, or traversal segments."
    )
  }
  if (
    !is.null(address$port) &&
      (!grepl("^[0-9]+$", address$port) ||
        as.numeric(address$port) < 1 ||
        as.numeric(address$port) > 65535)
  ) {
    .odb_abort("url must contain a valid TCP port.")
  }
  sub("/+$", "", httr2::url_build(address))
}

.odb_http_path <- function(path) {
  if (
    !is.character(path) ||
      !length(path) ||
      anyNA(path) ||
      !all(nzchar(path)) ||
      any(path %in% c(".", "..")) ||
      any(grepl("[/\\\\[:cntrl:]]", path))
  ) {
    .odb_abort(
      "path must contain nonempty relative path segments without slashes or traversal."
    )
  }
  paste(
    vapply(path, utils::URLencode, "", reserved = TRUE, repeated = TRUE),
    collapse = "/"
  )
}

.odb_http_query <- function(query) {
  if (!is.list(query)) {
    .odb_abort("query must be a named list.")
  }
  .odb_named_args(query, "query")
  if (any(names(query) %in% c(".req", ".multi", ".space"))) {
    .odb_abort("Reserved HTTP query option name.")
  }
  if (
    !all(vapply(
      query,
      function(x) {
        is.atomic(x) && length(x) == 1L && !is.na(x) && !is.object(x)
      },
      logical(1)
    ))
  ) {
    .odb_abort(
      "Each query value must be one non-missing string, number, or logical value."
    )
  }
  query
}

.odb_http_options <- function(timeout, ca_bundle) {
  .odb_seconds(timeout, "timeout")
  if (timeout <= 0) {
    .odb_abort("timeout must be positive.")
  }
  .odb_string(ca_bundle, "ca_bundle", optional = TRUE)
  invisible(NULL)
}

.odb_http_provider <- function(
  authorization,
  target,
  required_scopes,
  min_valid_for,
  session
) {
  .odb_bind(
    authorization,
    identity,
    target = target,
    required_scopes = required_scopes,
    cache_key = function(token) {
      token()
      NULL
    },
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_http_time <- function() unname(proc.time()[["elapsed"]])

.odb_http_diagnostics <- function(resp, service, credentials) {
  scalar <- function(value, pattern) {
    if (
      is.character(value) &&
        length(value) == 1L &&
        !is.na(value) &&
        !value %in% credentials &&
        grepl(pattern, value)
    ) {
      value
    } else {
      NULL
    }
  }
  uuid <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
  request_id <- NULL
  for (header in c(
    "X-Request-Id",
    if (service == "ClickHouse") "X-ClickHouse-Query-Id"
  )) {
    request_id <- scalar(httr2::resp_header(resp, header), uuid)
    if (!is.null(request_id)) break
  }
  code <- NULL
  if (service == "ClickHouse") {
    code <- scalar(
      httr2::resp_header(resp, "X-ClickHouse-Exception-Code"),
      "^[1-9][0-9]{0,8}$"
    )
  } else if (service %in% c("BigQuery", "PostgREST")) {
    body <- tryCatch(
      {
        if (length(httr2::resp_body_raw(resp)) > 65536L) {
          NULL
        } else {
          .odb_http_json(resp, service)
        }
      },
      error = function(e) NULL
    )
    if (is.list(body) && service == "PostgREST") {
      code <- scalar(body[["code"]], "^(PGRST[0-9]{3}|[0-9A-Z]{5})$")
    } else if (
      is.list(body) &&
        is.list(body[["error"]]) &&
        is.list(body[["error"]][["errors"]]) &&
        length(body[["error"]][["errors"]]) &&
        is.list(body[["error"]][["errors"]][[1L]])
    ) {
      reason <- body[["error"]][["errors"]][[1L]][["reason"]]
      known <- c(
        "accessDenied",
        "backendError",
        "billingNotEnabled",
        "duplicate",
        "internalError",
        "invalid",
        "invalidQuery",
        "notFound",
        "quotaExceeded",
        "rateLimitExceeded",
        "resourcesExceeded",
        "responseTooLarge",
        "stopped"
      )
      if (
        is.character(reason) &&
          length(reason) == 1L &&
          !is.na(reason) &&
          reason %in% known &&
          !reason %in% credentials
      ) {
        code <- reason
      }
    }
  }
  list(service_code = code, request_id = request_id)
}

.odb_http_perform <- function(req, service) {
  tryCatch(httr2::req_perform(req), error = function(error) {
    cause <- error
    transport_error <- NULL
    while (inherits(cause, "condition")) {
      classes <- class(cause)
      curl_classes <- classes[startsWith(classes, "curl_error_")]
      if (length(curl_classes)) {
        transport_error <- curl_classes[[1L]]
        break
      }
      cause <- cause$parent
    }
    timeout <- identical(transport_error, "curl_error_operation_timedout")
    message <- if (timeout) {
      paste0(service, " operation timed out.")
    } else {
      paste0(
        service,
        " transport failed. Check the endpoint, TLS, and network connection."
      )
    }
    .odb_abort(
      message,
      if (timeout) "timeout" else "request_failed",
      transport_error = transport_error
    )
  })
}

.odb_http_request <- function(
  token,
  req,
  service,
  timeout,
  ca_bundle = NULL,
  retry_401 = FALSE
) {
  deadline <- .odb_http_time() + timeout
  req <- httr2::req_options(req, followlocation = FALSE)
  if (!httr2::req_get_method(req) %in% c("GET", "HEAD")) {
    # libcurl can replay a write if a reused connection drops its response.
    req <- httr2::req_options(req, fresh_connect = TRUE, forbid_reuse = TRUE)
  }
  if (!is.null(ca_bundle)) {
    req <- httr2::req_options(req, cainfo = ca_bundle)
  }
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  credentials <- character()
  perform <- function(value) {
    force(value)
    credentials <<- union(credentials, value)
    remaining <- deadline - .odb_http_time()
    if (remaining <= 0) {
      .odb_abort(paste0(service, " operation timed out."), "timeout")
    }
    request <- httr2::req_timeout(req, remaining)
    request <- httr2::req_auth_bearer_token(request, value)
    .odb_http_perform(request, service)
  }
  resp <- perform(token())
  token(.check_only = TRUE)
  if (retry_401 && httr2::resp_status(resp) == 401L) {
    resp <- perform(token(force_refresh = TRUE))
    token(.check_only = TRUE)
  }
  if (.odb_http_time() >= deadline) {
    .odb_abort(paste0(service, " operation timed out."), "timeout")
  }
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    diagnostics <- .odb_http_diagnostics(resp, service, credentials)
    .odb_abort(
      paste0(
        service,
        " request failed (HTTP ",
        status,
        "). Check the endpoint, token audience, and user permissions."
      ),
      "request_failed",
      status = status,
      service_code = diagnostics$service_code,
      request_id = diagnostics$request_id
    )
  }
  resp
}

.odb_http_json <- function(resp, service, simplify = FALSE) {
  force(resp)
  tryCatch(
    {
      httr2::resp_check_content_type(
        resp,
        valid_types = "application/json",
        valid_suffix = "json"
      )
      jsonlite::parse_json(
        httr2::resp_body_string(resp, encoding = "UTF-8"),
        simplifyVector = simplify,
        bigint_as_char = TRUE
      )
    },
    error = function(e) {
      .odb_abort(
        paste0(service, " returned an invalid JSON response."),
        "invalid_response"
      )
    }
  )
}

.odb_http_date <- function(text, service) {
  invalid <- function() {
    .odb_abort(
      paste0(service, " returned an invalid date."),
      "invalid_response"
    )
  }
  present <- !is.na(text)
  if (any(present & !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text))) {
    invalid()
  }
  value <- tryCatch(as.Date(text, format = "%Y-%m-%d"), error = function(e) {
    invalid()
  })
  parts <- as.POSIXlt(value, tz = "UTC")
  canonical <- sprintf(
    "%04d-%02d-%02d",
    parts$year + 1900L,
    parts$mon + 1L,
    parts$mday
  )
  if (any(present & (is.na(value) | canonical != text))) {
    invalid()
  }
  value
}
