# Native API calls keep their argument matching and return values. Credentials
# are the only arguments supplied by the bridge.
.odb_api_arguments <- function(.fn, args, blocked, injected = "token") {
  if (!is.function(.fn)) {
    .odb_abort(".fn must be a native API function.")
  }
  nms <- names(args)
  if (!is.null(nms)) {
    if (anyNA(nms)) {
      .odb_abort("Native argument names must not be missing.")
    }
    .odb_options(args[nzchar(nms)], blocked = blocked)
  }
  if (!is.primitive(.fn)) {
    # Match placeholders, so positional authentication arguments are rejected
    # without evaluating caller arguments or acquiring a credential.
    supplied <- rep(list(quote(.odb_supplied)), length(args))
    names(supplied) <- nms
    credentials <- stats::setNames(
      rep(list(quote(.odb_injected)), length(injected)),
      injected
    )
    matched <- as.list(match.call(
      .fn,
      as.call(c(list(quote(.fn)), supplied, credentials)),
      expand.dots = FALSE
    ))[-1L]
    if ("..." %in% names(matched)) {
      matched <- c(matched[names(matched) != "..."], as.list(matched[["..."]]))
    }
    caller <- matched[
      !vapply(matched, identical, logical(1), quote(.odb_injected))
    ]
    .odb_options(caller[nzchar(names(caller))], blocked = blocked)
  }
  args
}

.odb_api_result <- function(result, check) {
  checked <- function(value, .visible = TRUE) {
    tryCatch(shiny::isolate(check()), error = function(error) {
      tryCatch(.odb_disconnect(value), error = function(error) {
        .odb_cleanup_failure()
      })
      stop(error)
    })
    if (.visible) value else invisible(value)
  }
  if (promises::is.promising(result$value)) {
    value <- promises::then(result$value, onFulfilled = checked)
  } else {
    return(checked(result$value, result$visible))
  }
  if (result$visible) value else invisible(value)
}

.odb_api_authorization <- function(authorization, session) {
  owner <- .odb_root_session(session)
  closed <- FALSE
  assert_owner <- function() {
    if (
      closed ||
        is.null(owner) ||
        isTRUE(owner$isClosed()) ||
        !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))
    ) {
      .odb_abort(
        "Use the API client in its owning, open Shiny session.",
        "authorization_unavailable"
      )
    }
  }
  assert_owner()
  reader <- .odb_authorization_reader(authorization)
  grant <- failure <- failure_key <- NULL
  epoch <- 0L
  changed <- shiny::reactiveVal(epoch)
  sync <- function() {
    assert_owner()
    next_grant <- next_failure <- NULL
    tryCatch(
      {
        next_grant <- reader()
        if (!is.null(next_grant)) {
          .odb_authorization_validate(next_grant)
          # Monitor reference availability without requiring any service's scopes
          # or token lifetime. A denied target must not retire other services.
          .odb_authorization_status(next_grant, NULL)
        }
      },
      error = function(error) {
        next_grant <<- NULL
        next_failure <<- error
      }
    )
    next_failure_key <- .odb_failure_key(next_failure)
    if (
      !identical(next_grant, grant) || !identical(next_failure_key, failure_key)
    ) {
      epoch <<- epoch + 1L
      changed(epoch)
    }
    grant <<- next_grant
    failure <<- next_failure
    failure_key <<- next_failure_key
    invisible(NULL)
  }
  observer <- shiny::observe(sync(), priority = 100, domain = owner)
  owner$onSessionEnded(function() {
    closed <<- TRUE
    grant <<- NULL
    observer$destroy()
  })
  function(.pin = FALSE) {
    assert_owner()
    shiny::isolate(sync())
    changed()
    if (!is.null(failure)) {
      stop(failure)
    }
    shiny::req(!is.null(grant))
    if (!.pin) {
      return(grant)
    }
    captured <- epoch
    function() {
      assert_owner()
      shiny::isolate(sync())
      changed()
      if (is.null(grant) || !identical(epoch, captured)) {
        .odb_abort(
          "This provider's authorization is no longer current.",
          "authorization_unavailable"
        )
      }
      invisible(NULL)
    }
  }
}
