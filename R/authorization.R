# Internal protocol supplied by module-created shinyOAuth connections.
.odb_authorization_field <- function(grant, name) {
  tryCatch(grant[[name]], error = function(e) NULL)
}

.odb_authorization_validate <- function(grant) {
  id <- .odb_authorization_field(grant, "id")
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id) ||
      !is.function(.odb_authorization_field(grant, "access_token")) ||
      !is.function(.odb_authorization_field(grant, "has_scopes"))) {
    .odb_abort(paste0("Pass auth$connection (without calling it), a reactive selecting a connection, ",
                      "or a module-created shinyOAuth connection."), "invalid_authorization")
  }
  invisible(grant)
}

.odb_authorization_has_scopes <- function(grant, required_scopes, target) {
  result <- grant$has_scopes(required_scopes, target = target)
  if (!is.logical(result) || length(result) != 1L || is.na(result)) {
    .odb_abort("has_scopes() must return one non-missing logical.", "invalid_authorization")
  }
  result
}

.odb_authorization_status <- function(grant, target) {
  method <- .odb_authorization_field(grant, if (is.null(target)) "summary" else "targets")
  if (!is.function(method)) return(NULL)
  value <- method()
  if (!is.null(target)) value <- value[[target]]
  value$status
}

.odb_authorization_denied <- function(grant, required_scopes, target, status) {
  if (identical(status, "insufficient_scope")) return(TRUE)
  if (!isTRUE(status %in% c("expired", "expiry_unknown"))) return(FALSE)
  # Export validation checks client and target requirements before lifetime.
  # Expiry alone must not retire a live database session. This public check
  # may renew an expired credential when the authorization can refresh it.
  tryCatch({
    shiny::isolate(grant$access_token(required_scopes = required_scopes,
      min_valid_for_seconds = 0, force_refresh = FALSE, async = FALSE, target = target))
    FALSE
  }, error = function(error) {
    if (!inherits(error, "shinyOAuth_access_error")) stop(error)
    reason <- error$context$reason
    if (identical(reason, "insufficient_scope")) return(TRUE)
    # These failures follow successful permission validation in shinyOAuth.
    if (isTRUE(reason %in% c("interaction_required", "refresh_unavailable", "lifetime_unavailable"))) return(FALSE)
    stop(error)
  })
}

.odb_authorization_reader <- function(authorization) {
  # Module fields live in reactiveValues; capture the accessor during server
  # setup without subscribing to its field outside a reactive consumer.
  shiny::isolate(force(authorization))
  if (is.function(authorization)) return(authorization)
  if (!is.null(authorization)) .odb_authorization_validate(authorization)
  function() authorization
}
