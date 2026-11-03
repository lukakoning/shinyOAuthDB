.odb_http_url <- function(url) {
  .odb_string(url, "url")
  address <- tryCatch(httr2::url_parse(url), error = function(e) NULL)
  if (is.null(address) || !identical(tolower(address$scheme), "https") ||
      is.null(address$hostname) || !nzchar(address$hostname) ||
      !is.null(address$username) || !is.null(address$password) ||
      !is.null(address$query) || !is.null(address$fragment) ||
      grepl("[[:space:]\\\\]", url) ||
      any(strsplit(utils::URLdecode(url), "/", fixed = TRUE)[[1L]] %in% c(".", ".."))) {
    .odb_abort("url must be an HTTPS address without credentials, a query, fragment, or traversal segments.")
  }
  if (!is.null(address$port) && (!grepl("^[0-9]+$", address$port) ||
      as.numeric(address$port) < 1 || as.numeric(address$port) > 65535)) {
    .odb_abort("url must contain a valid TCP port.")
  }
  sub("/+$", "", httr2::url_build(address))
}

.odb_http_path <- function(path) {
  if (!is.character(path) || !length(path) || anyNA(path) || any(!nzchar(path)) ||
      any(path %in% c(".", "..")) || any(grepl("[/\\\\[:cntrl:]]", path))) {
    .odb_abort("path must contain nonempty relative path segments without slashes or traversal.")
  }
  paste(vapply(path, utils::URLencode, "", reserved = TRUE, repeated = TRUE), collapse = "/")
}

.odb_http_query <- function(query) {
  if (!is.list(query)) .odb_abort("query must be a named list.")
  .odb_named_args(query, "query")
  if (any(names(query) %in% c(".req", ".multi", ".space"))) .odb_abort("Reserved HTTP query option name.")
  if (any(!vapply(query, function(x) is.atomic(x) && length(x) == 1L &&
      !is.na(x) && !is.object(x), logical(1)))) {
    .odb_abort("Each query value must be one non-missing string, number, or logical value.")
  }
  query
}

.odb_http_options <- function(timeout, ca_bundle) {
  .odb_seconds(timeout, "timeout")
  if (timeout <= 0) .odb_abort("timeout must be positive.")
  .odb_string(ca_bundle, "ca_bundle", optional = TRUE)
  invisible(NULL)
}

.odb_http_provider <- function(authorization, target, required_scopes, min_valid_for, session) {
  .odb_bind(authorization, identity, target = target, required_scopes = required_scopes,
    cache_key = function(token) { token(); NULL }, min_valid_for = min_valid_for, session = session)
}

.odb_http_time <- function() unname(proc.time()[["elapsed"]])

.odb_http_request <- function(token, req, service, timeout, ca_bundle = NULL, retry_401 = FALSE) {
  deadline <- .odb_http_time() + timeout
  req <- httr2::req_options(req, followlocation = FALSE)
  if (!is.null(ca_bundle)) req <- httr2::req_options(req, cainfo = ca_bundle)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  perform <- function(value) {
    force(value)
    remaining <- deadline - .odb_http_time()
    if (remaining <= 0) .odb_abort(paste0(service, " operation timed out."), "timeout")
    request <- httr2::req_timeout(req, remaining)
    request <- httr2::req_auth_bearer_token(request, value)
    tryCatch(httr2::req_perform(request), error = function(e) {
      .odb_abort(paste0(service, " transport failed. Check the endpoint, TLS, and network connection."),
        "request_failed")
    })
  }
  resp <- perform(token())
  token(.check_only = TRUE)
  if (retry_401 && httr2::resp_status(resp) == 401L) {
    resp <- perform(token(force_refresh = TRUE))
    token(.check_only = TRUE)
  }
  if (.odb_http_time() >= deadline) .odb_abort(paste0(service, " operation timed out."), "timeout")
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    .odb_abort(paste0(service, " request failed (HTTP ", status,
      "). Check the endpoint, token audience, and user permissions."), "request_failed", status = status)
  }
  resp
}

.odb_http_json <- function(resp, service, simplify = FALSE) {
  force(resp)
  tryCatch(httr2::resp_body_json(resp, simplifyVector = simplify, bigint_as_char = TRUE),
    error = function(e) .odb_abort(paste0(service, " returned an invalid JSON response."), "invalid_response"))
}
