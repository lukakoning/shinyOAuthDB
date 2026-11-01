# Native API calls keep their argument matching and return values. Credentials
# are the only arguments supplied by the bridge.
.odb_api_arguments <- function(.fn, args, blocked, injected = "token") {
  if (!is.function(.fn)) .odb_abort(".fn must be a native API function.")
  nms <- names(args)
  if (!is.null(nms)) {
    if (anyNA(nms)) .odb_abort("Native argument names must not be missing.")
    .odb_options(args[nzchar(nms)], blocked = blocked)
  }
  if (!is.primitive(.fn)) {
    # Match placeholders, so positional authentication arguments are rejected
    # without evaluating caller arguments or acquiring a credential.
    supplied <- rep(list(quote(.odb_supplied)), length(args))
    names(supplied) <- nms
    credentials <- stats::setNames(rep(list(quote(.odb_injected)), length(injected)), injected)
    matched <- as.list(match.call(.fn,
      as.call(c(list(quote(.fn)), supplied, credentials)), expand.dots = FALSE))[-1L]
    if ("..." %in% names(matched)) {
      matched <- c(matched[names(matched) != "..."], as.list(matched[["..."]]))
    }
    caller <- matched[!vapply(matched, identical, logical(1), quote(.odb_injected))]
    .odb_options(caller[nzchar(names(caller))], blocked = blocked)
  }
  args
}

.odb_api_authorization <- function(authorization, session) {
  owner <- .odb_root_session(session)
  assert_owner <- function() {
    if (is.null(owner) || isTRUE(owner$isClosed()) ||
        !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))) {
      .odb_abort("Use the API client in its owning, open Shiny session.",
                 "authorization_unavailable")
    }
  }
  assert_owner()
  reader <- .odb_authorization_reader(authorization)
  function() {
    assert_owner()
    grant <- reader()
    shiny::req(!is.null(grant))
    .odb_authorization_validate(grant)
    grant
  }
}
