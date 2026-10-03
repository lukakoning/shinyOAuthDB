# Worker payload is a named NSE export, never a global credential object.
utils::globalVariables(".payload")

#' Run an existing database-package function in a guarded background task
#'
#' @description
#' Keep native database APIs while acquiring the signed-in user's credential on
#' the Shiny process and performing the operation on a worker. The worker opens
#' its own connection; the session's cached connection is never serialized.
#'
#' @param db A handle returned by [oauth_db_session()].
#' @param fun A supported exported package function, supplied directly, such as
#'   `DBI::dbGetQuery`, `DBI::dbExecute`, `fabricQueryR::fabric_kql_query`, or
#'   `brickster::db_sql_query`. Closures and wrappers are not accepted.
#' @param executor Worker engine, either `"mirai"` (default) or `"future"`.
#'   Configure `mirai::daemons()` or `future::plan()` in the app. This function
#'   never changes those global settings.
#' @param credential_budget Positive number of seconds for which the credential
#'   must remain valid. Workers cannot refresh and reject expired credentials
#'   and results that arrive after this budget. This does not stop or undo a
#'   database operation that has already been submitted.
#' @param pending What to do when invoked while busy: `"serial"` queues each
#'   invocation, `"latest"` retains only the newest waiting invocation, and
#'   `"ignore"` discards new invocations. `"latest"` requires `effect = "read"`.
#' @param effect Declare whether this operation is `"unknown"`, `"read"`, or
#'   `"write"`. SQL text is not parsed to guess its effects.
#' @param ... Named defaults for the native function. `invoke()` can override
#'   these operation arguments, but cannot override credentials or source fields.
#'
#' @details
#' Create a task once inside `server()`. Call `$invoke(...)` with plain,
#' serializable operation arguments, and `$result()` inside a reactive output.
#' Source bindings and credentials are supplied by the adapter. Authorization
#' is captured when an invocation is queued, but tokens are obtained only when
#' it starts. Results and errors from an earlier authorization are hidden.
#'
#' `$cancel()` drops waiting work and hides the active outcome. It does not
#' cancel a submitted database statement or undo a write. Credentials already
#' supplied to a worker cannot be recalled on logout. Use least-privilege database
#' grants and native statement timeouts for resource control.
#'
#' Worker errors are deliberately reported without the driver's raw condition,
#' which can include credentials, connection strings, or SQL. This package does
#' not log the original worker condition; worker warnings and messages are also
#' suppressed for the same reason.
#'
#' @returns A small object with `$invoke(...)`, reactive `$status()` and
#'   `$result()`, and `$cancel()`. Status is `"initial"`, `"running"`,
#'   `"success"`, or `"error"`. `invoke()` invisibly returns whether the
#'   invocation was accepted. `result()` follows `shiny::ExtendedTask` semantics
#'   for an unstarted or running operation.
#' @export
oauth_db_task <- function(db, fun, executor = c("mirai", "future"),
                          credential_budget = 120,
                          pending = c("serial", "latest", "ignore"),
                          effect = c("unknown", "read", "write"), ...) {
  executor <- match.arg(executor)
  pending <- match.arg(pending)
  effect <- match.arg(effect)
  if (!inherits(db, "oauth_db_handle") ||
      !all(vapply(c(".capture", ".is_current", ".acquire", ".source"),
                  function(name) is.function(db[[name]]), logical(1)))) {
    stop("db must be an oauth_db_session() handle.", call. = FALSE)
  }
  if (!is.numeric(credential_budget) || length(credential_budget) != 1L ||
      is.na(credential_budget) || !is.finite(credential_budget) ||
      credential_budget <= 0) {
    stop("credential_budget must be one positive finite number.", call. = FALSE)
  }
  if (pending == "latest" && effect != "read") {
    stop("pending = 'latest' requires an explicit effect = 'read'.", call. = FALSE)
  }
  session <- shiny::getDefaultReactiveDomain()
  if (is.null(session)) {
    stop("Create the task inside a Shiny server session.", call. = FALSE)
  }
  if (!requireNamespace(executor, quietly = TRUE)) {
    stop(paste0("Install the ", executor, " package for this executor."), call. = FALSE)
  }
  source <- db$.source()
  spec <- .odb_operation_spec(source, fun)
  scopes <- spec$required_scopes
  defaults <- list(...)
  .odb_task_check_args(defaults, spec)
  .odb_task_check_plain(source, "source")

  state <- new.env(parent = emptyenv())
  state$busy <- FALSE
  state$closed <- FALSE
  state$version <- 0L
  state$sequence <- 0L
  state$queue <- list()
  active <- shiny::reactiveVal(NULL)

  check_session <- function() {
    domain <- shiny::getDefaultReactiveDomain()
    if (state$closed || isTRUE(session$isClosed()) || is.null(domain) ||
        !identical(session$rootScope(), domain$rootScope())) {
      stop("Use this task in its owning, open Shiny session.", call. = FALSE)
    }
  }
  is_current <- function(entry, isolated = FALSE) {
    if (is.null(entry) || state$closed || isTRUE(session$isClosed()) ||
        !identical(entry$version, state$version)) return(FALSE)
    if (isolated) {
      isTRUE(shiny::isolate(db$.is_current(entry$capture, required_scopes = scopes)))
    } else {
      isTRUE(db$.is_current(entry$capture, required_scopes = scopes))
    }
  }
  run_next <- function() {
    if (state$closed || state$busy || length(state$queue) == 0L) return(invisible(NULL))
    entry <- state$queue[[1L]]
    state$queue <- state$queue[-1L]
    state$busy <- TRUE
    active(entry)
    task$invoke(entry)
    invisible(NULL)
  }
  finish <- function() {
    state$busy <- FALSE
    if (!state$closed && length(state$queue)) {
      later::later(function() shiny::withReactiveDomain(session, run_next()), delay = 0)
    }
  }
  task <- shiny::ExtendedTask$new(function(entry) {
    # ExtendedTask masks reactive access. Only the owning process can consult
    # the live authorization; isolate avoids capturing it in a worker closure.
    operation <- tryCatch({
      if (!is_current(entry, isolated = TRUE)) {
        stop("The authorization changed before starting.", call. = FALSE)
      }
      deadline <- .odb_task_now() + credential_budget
      credential <- shiny::isolate(db$.acquire(
        entry$capture, required_scopes = scopes,
        min_valid_for = credential_budget, async = TRUE
      ))
      promises::then(promises::promise_resolve(credential), function(token) {
        if (!is_current(entry, isolated = TRUE)) {
          stop("The authorization changed before submission.", call. = FALSE)
        }
        if (!is.character(token) || length(token) != 1L || is.na(token) || !nzchar(token)) {
          stop("Credential acquisition did not return an access token.", call. = FALSE)
        }
        payload <- list(source = source, spec = spec, token = token,
                        deadline = deadline, args = entry$args,
                        capture = entry$capture, invocation_id = entry$id)
        .odb_task_dispatch(payload, executor)
      })
    }, error = function(error) promises::promise_reject(error))
    # Attach rejection handling AFTER acquisition and worker dispatch. Errors
    # thrown by either fulfillment handler therefore become safe envelopes too.
    outcome <- promises::then(operation, function(value) {
      if (!is.list(value) || !identical(value$.oauth_db_outcome, TRUE)) {
        return(.odb_task_outcome(error = "executor"))
      }
      value
    })
    outcome <- promises::catch(outcome, function(error) {
      .odb_task_outcome(error = "acquisition_or_executor")
    })
    outcome <- promises::then(outcome, function(value) {
      value$invocation_id <- entry$id
      value
    })
    promises::finally(outcome, finish)
  })
  session$onSessionEnded(function() {
    state$closed <- TRUE
    state$version <- state$version + 1L
    state$queue <- list()
    active(NULL)
  })

  structure(list(
    invoke = function(...) {
      check_session()
      args <- list(...)
      .odb_task_check_args(args, spec)
      merged <- defaults
      merged[names(args)] <- args
      args <- merged
      .odb_task_check_args(args, spec)
      if (state$busy && pending == "ignore") return(invisible(FALSE))
      capture <- db$.capture(required_scopes = scopes)
      .odb_task_check_plain(capture, "authorization capture")
      state$sequence <- state$sequence + 1L
      entry <- list(capture = capture, args = args, version = state$version,
                    id = state$sequence)
      if (state$busy && pending == "latest") state$queue <- list()
      state$queue <- c(state$queue, list(entry))
      run_next()
      invisible(TRUE)
    },
    status = function() {
      check_session()
      entry <- active()
      if (!is_current(entry)) return("initial")
      status <- task$status()
      if (status == "success") {
        outcome <- task$result()
        if (!identical(outcome$invocation_id, entry$id)) return("initial")
        if (!is.null(outcome$error)) return("error")
      }
      status
    },
    result = function() {
      check_session()
      entry <- active()
      # Guard BEFORE reading ExtendedTask$result(), including error paths.
      shiny::req(is_current(entry))
      outcome <- task$result()
      shiny::req(identical(outcome$invocation_id, entry$id))
      if (!is.null(outcome$error)) {
        message <- switch(outcome$error,
          credential_expired = "The worker credential budget expired. The database operation may already have completed.",
          operation = "The database operation failed. Check the service and operation arguments.",
          "The database task could not start or complete. Check authorization and worker configuration."
        )
        .odb_abort(message, "task_error", code = outcome$error)
      }
      outcome$value
    },
    cancel = function() {
      check_session()
      state$version <- state$version + 1L
      state$queue <- list()
      active(NULL)
      invisible(NULL)
    }
  ), class = "oauth_db_task")
}

.odb_task_outcome <- function(value = NULL, error = NULL) {
  list(.oauth_db_outcome = TRUE, value = value, error = error)
}

.odb_task_now <- function() as.numeric(Sys.time())

.odb_task_check_args <- function(args, spec) {
  if (length(args) && (is.null(names(args)) || any(!nzchar(names(args))) ||
                       anyDuplicated(names(args)))) {
    stop("Native task arguments must have unique, nonempty names.", call. = FALSE)
  }
  protected <- unique(c(spec$credential_arg, spec$connection_arg,
                        names(spec$bindings), spec$protected_args))
  if (any(tolower(names(args)) %in% tolower(protected))) {
    stop("The task supplies credentials and source arguments; these cannot be overridden.",
         call. = FALSE)
  }
  native_formals <- setdiff(names(formals(getExportedValue(spec$package, spec$fun))), "...")
  exact_native <- names(args) %in% native_formals
  protected_prefix <- vapply(tolower(names(args)), function(name) {
    any(startsWith(tolower(protected), name))
  }, logical(1))
  if (any(protected_prefix & !exact_native)) {
    stop("Native task argument abbreviations cannot match protected credentials or source fields; use full argument names.",
         call. = FALSE)
  }
  .odb_task_check_plain(args, "task arguments")
  invisible(NULL)
}

.odb_task_check_plain <- function(value, label, depth = 0L) {
  if (depth >= 50L) {
    stop(paste0(label, " exceed the supported nesting limit."), call. = FALSE)
  }
  # DBI::Id and DBI::SQL contain names/text, rather than a live driver object.
  # Keep these native argument types so tasks can use ordinary DBI calls.
  safe_dbi_s4 <- isS4(value) && length(class(value)) == 1L &&
    class(value)[[1L]] %in% c("Id", "SQL") &&
    identical(attr(class(value), "package"), "DBI")
  if (is.environment(value) || is.function(value) || (isS4(value) && !safe_dbi_s4) ||
      typeof(value) %in% c("externalptr", "weakref", "symbol", "language", "pairlist")) {
    stop(paste0(label, " must contain only plain serializable data, without functions or live connections."),
         call. = FALSE)
  }
  if (is.list(value)) lapply(value, .odb_task_check_plain, label = label, depth = depth + 1L)
  attrs <- attributes(value)
  if (!is.null(attrs)) lapply(attrs, .odb_task_check_plain, label = label, depth = depth + 1L)
  invisible(NULL)
}

.odb_task_dispatch <- function(payload, executor) {
  if (executor == "mirai") {
    worker <- mirai::mirai(
      get(".odb_run_operation", envir = asNamespace("shinyOAuthDB"))(.payload),
      .payload = payload
    )
    promises::as.promise(worker)
  } else {
    # Only .payload is exported. In particular, no surrounding Shiny/session
    # closure is discovered or sent by future's automatic globals scanner.
    promises::future_promise(
      get(".odb_run_operation", envir = asNamespace("shinyOAuthDB"))(.payload),
      globals = list(.payload = payload), packages = "shinyOAuthDB",
      seed = FALSE, conditions = character(), stdout = FALSE
    )
  }
}

.odb_run_operation <- function(payload) {
  tryCatch(suppressWarnings(suppressMessages({
    credential <- function(force_refresh = FALSE, async = FALSE, ...) {
      if (isTRUE(force_refresh)) {
        stop("Workers cannot refresh credentials.", call. = FALSE)
      }
      if (.odb_task_now() >= payload$deadline) {
        stop(structure(list(message = "Worker credential expired.", call = NULL),
                       class = c("oauth_db_worker_expired", "error", "condition")))
      }
      if (isTRUE(async)) return(promises::promise_resolve(payload$token))
      payload$token
    }
    credential()
    provider <- .odb_adapter_token_provider(payload$source, credential)
    args <- c(payload$spec$bindings, payload$args)
    if (!is.null(payload$spec$connection_arg)) {
      con <- .odb_adapter_connect(payload$source, provider)
      on.exit(try(.odb_adapter_disconnect(payload$source, con), silent = TRUE), add = TRUE)
      args[[payload$spec$connection_arg]] <- con
    } else {
      args[[payload$spec$credential_arg]] <- provider
    }
    # Resolve by namespace inside the worker; never deserialize an app closure.
    native <- getExportedValue(payload$spec$package, payload$spec$fun)
    value <- do.call(native, args)
    credential()
    .odb_task_check_plain(value, "Task results")
    .odb_task_outcome(value = value)
  })), oauth_db_worker_expired = function(error) {
    .odb_task_outcome(error = "credential_expired")
  }, error = function(error) {
    .odb_task_outcome(error = "operation")
  })
}
