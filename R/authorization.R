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

.odb_authorization_call <- function(grant, method, args) {
  fun <- .odb_authorization_field(grant, method)
  accepts <- names(formals(fun))
  if (!"target" %in% accepts && !"..." %in% accepts) {
    if (!is.null(args$target)) .odb_abort("This authorization does not support named token targets.",
                                        "unsupported_authorization_target")
    args$target <- NULL
  }
  do.call(fun, args)
}

.odb_authorization_has_scopes <- function(grant, scopes, target) {
  result <- .odb_authorization_call(grant, "has_scopes", list(scopes = scopes, target = target))
  if (!is.logical(result) || length(result) != 1L || is.na(result)) {
    .odb_abort("has_scopes() must return one non-missing logical.", "invalid_authorization")
  }
  result
}

.odb_authorization_reader <- function(authorization) {
  force(authorization)
  if (is.function(authorization)) return(authorization)
  if (!is.null(authorization)) .odb_authorization_validate(authorization)
  function() authorization
}
