.odb_abort <- function(message, reason = "invalid_configuration", ...) {
  rlang::abort(
    message,
    class = c(paste0("shinyOAuthDB_", reason), "shinyOAuthDB_error"),
    reason = reason,
    ...
  )
}

# Conditions can be recreated on every read, with fresh traces. Notify Shiny
# only when the failure itself changes, not when its condition object changes.
.odb_failure_key <- function(error) {
  if (is.null(error)) return(NULL)
  reason <- error$context$reason
  if (is.null(reason)) reason <- error$reason
  list(class = class(error), detail = if (is.null(reason)) conditionMessage(error) else reason)
}

.odb_string <- function(value, name, optional = FALSE) {
  if (optional && is.null(value)) {
    return(invisible(value))
  }
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value)
  ) {
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
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      !is.finite(value) ||
      value < 0 ||
      (positive && value == 0)
  ) {
    .odb_abort(paste0(
      name,
      " must be a finite ",
      if (positive) "positive" else "non-negative",
      " number of seconds."
    ))
  }

  invisible(value)
}

.odb_scopes <- function(value, name = "required_scopes") {
  if (
    !is.character(value) ||
      anyNA(value) ||
      any(!nzchar(value)) ||
      any(grepl("[[:space:]]", value))
  ) {
    .odb_abort(paste0(
      name,
      " must be a character vector of individual scope strings."
    ))
  }

  unique(value)
}

.odb_require <- function(package, feature = package, version = NULL) {
  if (
    !requireNamespace(package, quietly = TRUE) ||
      (!is.null(version) &&
        utils::packageVersion(package) < package_version(version))
  ) {
    .odb_abort(
      paste0(
        "Install ",
        package,
        if (!is.null(version)) paste0(" >= ", version),
        " to use ",
        feature,
        "."
      ),
      "missing_dependency"
    )
  }

  invisible(TRUE)
}

.odb_root_session <- function(session) {
  if (is.null(session) || !is.function(session$rootScope)) {
    return(NULL)
  }

  session$rootScope()
}
