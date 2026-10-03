.odb_abort <- function(message, reason = "invalid_configuration", ...) {
  rlang::abort(message, class = c(paste0("shinyOAuthDB_", reason), "shinyOAuthDB_error"),
               reason = reason, ...)
}

.odb_string <- function(value, name, optional = FALSE) {
  if (optional && is.null(value)) return(invisible(value))
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    .odb_abort(paste0(name, " must be one non-empty character string."))
  }
  invisible(value)
}

.odb_flag <- function(value, name) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    .odb_abort(paste0(name, " must be TRUE or FALSE."))
  }
  invisible(value)
}

.odb_seconds <- function(value, name, positive = FALSE) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
      value < 0 || (positive && value == 0)) {
    .odb_abort(paste0(name, " must be a finite ", if (positive) "positive" else "non-negative", " number of seconds."))
  }
  invisible(value)
}

.odb_scopes <- function(value, name = "required_scopes") {
  if (!is.character(value) || anyNA(value) || any(!nzchar(value)) ||
      any(grepl("[[:space:]]", value))) {
    .odb_abort(paste0(name, " must be a character vector of individual scope strings."))
  }
  unique(value)
}

.odb_require <- function(package, feature = package, version = NULL) {
  if (!requireNamespace(package, quietly = TRUE) ||
      (!is.null(version) && utils::packageVersion(package) < package_version(version))) {
    .odb_abort(paste0("Install ", package, if (!is.null(version)) paste0(" >= ", version),
                      " to use ", feature, "."), "missing_dependency")
  }
  invisible(TRUE)
}

.odb_root_session <- function(session) {
  if (is.null(session) || !is.function(session$rootScope)) return(NULL)
  session$rootScope()
}

.odb_live_value <- function(value) {
  inherits(value, c("DBIConnection", "DBIResult", "tbl_sql", "tbl_lazy", "promise",
                    "OAuthConnection", "oauth_db_authorization", "ArrowObject", "RecordBatchReader")) ||
    typeof(value) == "externalptr"
}

.odb_assert_materialized <- function(value, depth = 0L) {
  if (.odb_live_value(value) || is.environment(value) || is.function(value) || isS4(value) ||
      typeof(value) %in% c("weakref", "symbol", "language", "pairlist")) {
    .odb_abort("Return materialized data; live connections, lazy queries, promises and callbacks cannot leave this scope.",
               "unsupported_result")
  }
  if (depth < 50L && is.list(value)) {
    for (element in value) .odb_assert_materialized(element, depth + 1L)
  } else if (depth >= 50L) {
    .odb_abort("Result nesting exceeds the materialized result limit.", "unsupported_result")
  }
  attrs <- attributes(value)
  if (!is.null(attrs)) for (attribute in attrs) .odb_assert_materialized(attribute, depth + 1L)
  invisible(value)
}
