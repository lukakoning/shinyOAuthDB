#' Adapt a custom user authorization to the database connection contract
#'
#' shinyOAuth module connections work directly. This helper lets another
#' authentication package expose the same small interface without inheriting
#' from shinyOAuth's class or handing refresh credentials to the bridge.
#'
#' @param id Stable, non-secret ID for this particular authorization. Use a new
#'   ID for a replacement login/grant, even for the same user. Token rotation
#'   preserves the ID. Keep the object stable for that authorization too.
#' @param access_token Callback accepting `required_scopes`, `min_valid_for`,
#'   `force_refresh`, `async`, and optionally `target`. It must obtain the
#'   selected user's bearer token, enforce those requirements, and fail after
#'   this authorization ends. It must not follow a replacement login. For
#'   `async = TRUE`, return a promise without blocking the Shiny process.
#' @param has_scopes Callback accepting `scopes` and optionally `target`,
#'   returning exactly one non-missing logical. It checks current authorization
#'   permission evidence and liveness, independent of cached token expiry.
#'   Read reactive state so logout and permission loss notify consumers.
#' @param targets Optional callback with no arguments returning the same named
#'   target metadata as shinyOAuth `targets()`. A target's
#'   `list(status = "not_acquired")` permits its first credential acquisition.
#'   Without this callback, scope checks must already cover the operation.
#'
#' @details
#' Callbacks may omit `target` for a single-resource connection; the bridge only
#' omits that argument when the source target is `NULL`. A named target is never
#' silently discarded. Other required arguments must be accepted explicitly
#' or through `...` and their meaning must be honored.
#'
#' This is an adapter, not another login or refresh controller. The caller owns
#' user binding, verified permission evidence, lifetime checks, refresh and
#' reactive authorization changes. The bridge enforces its owning Shiny
#' session, captures authorization identity, and guards native transports and
#' task outcomes. A direct list or environment with this interface also works;
#' use this helper to map a different authentication package's method names.
#'
#' @return A custom authorization object usable directly, through a no-argument
#'   accessor or in a reactive supplied to [oauth_db_session()]. Printing the
#'   adapter does not expose IDs, callbacks or credentials.
#' @export
oauth_db_authorization <- function(id, access_token, has_scopes, targets = NULL) {
  .odb_string(id, "authorization ID")
  .odb_authorization_method(access_token, "access_token", c("required_scopes", "min_valid_for", "force_refresh", "async"))
  .odb_authorization_method(has_scopes, "has_scopes", "scopes")
  if (!is.null(targets)) .odb_authorization_method(targets, "targets", character())
  connection <- list(id = id, access_token = access_token, has_scopes = has_scopes)
  result <- list(id = id,
    access_token = function(required_scopes = character(), min_valid_for = 60,
                            force_refresh = FALSE, async = FALSE, target = NULL) {
      .odb_scopes(required_scopes)
      .odb_seconds(min_valid_for, "min_valid_for")
      .odb_flag(force_refresh, "force_refresh")
      .odb_flag(async, "async")
      .odb_string(target, "target", optional = TRUE)
      value <- .odb_authorization_call(connection, "access_token", list(
        required_scopes = required_scopes, min_valid_for = min_valid_for,
        force_refresh = force_refresh, async = async, target = target))
      if (!async && inherits(value, "promise")) {
        .odb_abort("Synchronous access_token() must return a bearer token, not a promise; use async = TRUE for asynchronous acquisition.", "invalid_credential")
      }
      if (async && !inherits(value, "promise")) return(promises::promise_resolve(value))
      value
    },
    has_scopes = function(scopes, target = NULL) {
      .odb_scopes(scopes, "scopes")
      .odb_string(target, "target", optional = TRUE)
      .odb_authorization_has_scopes(connection, scopes, target)
    })
  if (!is.null(targets)) result$targets <- targets
  structure(result, class = "oauth_db_authorization")
}

.odb_authorization_field <- function(connection, name) {
  tryCatch(connection[[name]], error = function(e) NULL)
}

.odb_authorization_method <- function(fun, name, required) {
  if (!is.function(fun)) .odb_abort(paste0("Authorization must provide a callable ", name, "() method."), "invalid_authorization")
  arguments <- names(formals(fun))
  if (!"..." %in% arguments && !all(required %in% arguments)) {
    .odb_abort(paste0("Authorization ", name, "() must accept: ", paste(required, collapse = ", "), ". Use oauth_db_authorization() to adapt another interface."), "invalid_authorization")
  }
  invisible(fun)
}

.odb_authorization_validate <- function(connection) {
  .odb_string(.odb_authorization_field(connection, "id"), "authorization ID")
  .odb_authorization_method(.odb_authorization_field(connection, "access_token"), "access_token",
                            c("required_scopes", "min_valid_for", "force_refresh", "async"))
  .odb_authorization_method(.odb_authorization_field(connection, "has_scopes"), "has_scopes", "scopes")
  targets <- .odb_authorization_field(connection, "targets")
  if (!is.null(targets)) .odb_authorization_method(targets, "targets", character())
  invisible(connection)
}

.odb_authorization_call <- function(connection, method, args) {
  fun <- .odb_authorization_field(connection, method)
  .odb_authorization_method(fun, method, setdiff(names(args), "target"))
  accepts <- names(formals(fun))
  if ("target" %in% names(args) && !"target" %in% accepts && !"..." %in% accepts) {
    if (!is.null(args$target)) {
      .odb_abort("This authorization cannot select a named token target. Adapt its target routing or use a single-resource source with target = NULL.", "unsupported_authorization_target")
    }
    args$target <- NULL
  }
  do.call(fun, args)
}

.odb_authorization_has_scopes <- function(connection, scopes, target) {
  value <- .odb_authorization_call(connection, "has_scopes", list(scopes = scopes, target = target))
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    .odb_abort("Authorization has_scopes() must return one non-missing logical value.", "invalid_authorization")
  }
  value
}

.odb_authorization_reader <- function(authorization) {
  if (shiny::is.reactive(authorization)) return(authorization)
  if (is.function(authorization)) {
    required <- formals(authorization)
    required <- required[names(required) != "..."]
    if (length(required) && any(vapply(required, function(value) identical(value, quote(expr = )), logical(1)))) {
      .odb_abort("authorization accessor must be callable without arguments.", "invalid_authorization")
    }
    return(shiny::reactive(authorization()))
  }
  if (!is.null(authorization)) .odb_authorization_validate(authorization)
  shiny::reactive(authorization)
}

#' @export
print.oauth_db_authorization <- function(x, ...) {
  cat("<oauth_db_authorization: caller-owned user authorization; credentials redacted>\n")
  invisible(x)
}
