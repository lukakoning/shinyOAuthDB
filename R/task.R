#' Fetch data in the background as the signed-in user
#'
#' Create a task inside `server()` from an existing database helper or API
#' client. Credentials stay coordinated by the owning Shiny session; each
#' invocation opens its own connection or client in a mirai worker.
#'
#' @param source A database helper such as [oauth_db_azure_postgres()] (pass
#'   `con`, not `con()`), or a shinyOAuthDB API client.
#' @param method Operation name. `"query"` uses `DBI::dbGetQuery()` for DBI
#'   connections and `$query()` for API clients. `"execute"` uses
#'   `DBI::dbExecute()` for DBI connections. Other names select native client
#'   methods, e.g. `"select"` or `"search"`. A self-contained function defined
#'   at the top level may instead take the worker's connection/client as its
#'   first argument. Use namespace-qualified functions inside that function.
#' @param min_valid_for Minimum token lifetime requested before dispatch,
#'   in seconds. Allow for queueing and the operation. Workers do not receive
#'   refresh tokens and cannot refresh a copied access token.
#' @param compute Optional mirai compute-profile name. Use a separate profile
#'   for database work to reserve the default pool for OAuth operations.
#' @return A task with `$invoke(...)`, `$result()`, `$status()` and `$cancel()`.
#'   Invocation arguments go to the selected operation. Busy invocations are
#'   ignored and return `FALSE`; accepted invocations return `TRUE`, invisibly.
#'   `result()` waits quietly before completion, checks authorization on every
#'   read, and returns ordinary R data. Native handles cannot leave the worker.
#'   Status is `"initial"`, `"running"`, `"success"` or `"error"`. Cancelled or
#'   invalidated results report `"initial"` until another invocation is accepted.
#' @details
#' mirai (2.5.1 or newer) is installed with shinyOAuthDB. Configure
#' `mirai::daemons()` once before the server starts, and stop those workers
#' when the app stops. The task never starts a worker pool itself. Enable
#' `async = TRUE` on shinyOAuth's module separately for background OAuth
#' operations.
#'
#' Sign-out, account changes, permission loss and session end invalidate results
#' and attempt to cancel pending worker work. Cancellation cannot undo a query
#' or write already accepted by a server. Operations are never automatically
#' replayed after a credential change. A worker's token snapshot expires after
#' the requested lifetime budget; HTTP 401 does not refresh that snapshot or
#' replay the operation. Choose sufficient lifetime for long polling/downloads.
#'
#' API tasks reuse the backend's request, parameter, TLS and result-handling
#' code. Fabric API tasks acquire all token groups configured on their source;
#' configure `targets` for the services used by that task. Resolve reactive
#' connection usernames in the owning session; pass query inputs to `invoke()`.
#' @examples
#' \dontrun{
#' # Once at app startup:
#' mirai::daemons(2)
#' shiny::onStop(function() mirai::daemons(0))
#'
#' # Inside server(), with con created by a database helper:
#' rows <- oauth_db_task(con)
#' shiny::observeEvent(input$load, rows$invoke("SELECT current_user"))
#' output$rows <- shiny::renderTable(rows$result())
#'
#' # An HTTP client uses the same pattern:
#' orders <- oauth_db_task(postgrest, method = "select")
#' shiny::observeEvent(input$load_orders, {
#'   orders$invoke("orders", order = "id.asc", limit = 20L)
#' })
#' output$orders <- shiny::renderTable(orders$result())
#' }
#' @export
oauth_db_task <- function(
  source,
  method = "query",
  min_valid_for = 120,
  compute = NULL
) {
  .odb_require("mirai", version = "2.5.1")
  .odb_string(compute, "compute", optional = TRUE)
  .odb_seconds(min_valid_for, "min_valid_for")
  if (min_valid_for <= 0) {
    .odb_abort("min_valid_for must be positive for a task.")
  }
  if (is.function(method)) {
    method <- .odb_task_function(method)
  } else {
    .odb_string(method, "method")
  }
  spec <- .odb_task_source(source)
  owner <- spec$plans[[1L]]$owner
  assert_owner <- function() {
    if (
      isTRUE(owner$isClosed()) ||
        !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))
    ) {
      .odb_abort(
        "Use the task in its owning, open Shiny session.",
        "authorization_unavailable"
      )
    }
  }
  assert_owner()
  for (plan in spec$plans) {
    plan$enable_async()
  }
  running <- NULL
  active <- NULL
  valid <- shiny::reactiveVal(NULL)
  current <- function(check, ready = FALSE) {
    tryCatch(
      {
        check(.ready = ready)
        TRUE
      },
      error = function(error) {
        if (inherits(error, "shinyOAuthDB_authorization_pending")) NA else FALSE
      }
    )
  }
  cancel_worker <- function() {
    if (!is.null(running)) {
      tryCatch(mirai::stop_mirai(running), error = function(error) NULL)
      running <<- NULL
    }
    invisible(NULL)
  }
  task <- shiny::ExtendedTask$new(function(pins, worker, arguments, check) {
    shiny::isolate({
      pending <- lapply(seq_along(pins), function(index) {
        budget <- max(min_valid_for, spec$plans[[index]]$min_valid_for)
        promises::then(
          pins[[index]](.async = TRUE, .min_valid_for = budget),
          function(token) {
            list(token = token, until = .odb_task_time() + budget)
          }
        )
      })
      promises::then(
        promises::promise_all(.list = pending),
        function(snapshots) {
          if (!isTRUE(shiny::isolate(current(check, ready = TRUE)))) {
            return(NULL)
          }
          tokens <- lapply(snapshots, function(snapshot) snapshot$token)
          until <- vapply(snapshots, function(snapshot) snapshot$until, 0)
          running <<- mirai::mirai(
            {
              get(".odb_task_job", asNamespace("shinyOAuthDB"))(
                worker,
                tokens,
                until,
                method,
                arguments
              )
            },
            worker = worker,
            tokens = tokens,
            until = until,
            method = method,
            arguments = arguments,
            .compute = compute
          )
          promises::then(
            running,
            onFulfilled = function(value) {
              running <<- NULL
              if (isFALSE(shiny::isolate(current(check)))) {
                return(NULL)
              }
              value
            },
            onRejected = function(error) {
              running <<- NULL
              if (!isFALSE(shiny::isolate(current(check)))) {
                return(list(ok = FALSE, error = error))
              }
              NULL
            }
          )
        },
        onRejected = function(error) {
          if (!isFALSE(shiny::isolate(current(check)))) {
            return(list(ok = FALSE, error = error))
          }
          NULL
        }
      )
    })
  })
  watcher <- shiny::observe(
    {
      for (plan in spec$plans) {
        plan$watch()
      }
      check <- valid()
      if (!is.null(check) && isFALSE(current(check))) {
        if (!is.null(active)) {
          active$valid <- FALSE
        }
        cancel_worker()
      }
    },
    priority = 100,
    domain = owner
  )
  owner$onSessionEnded(function() {
    cancel_worker()
    watcher$destroy()
  })
  structure(
    list(
      invoke = function(...) {
        assert_owner()
        if (shiny::isolate(task$status()) == "running") {
          return(invisible(FALSE))
        }
        if (!isTRUE(mirai::daemons_set(.compute = compute))) {
          .odb_abort(
            "Configure mirai::daemons() before invoking a database task."
          )
        }
        arguments <- list(...)
        expressions <- as.list(substitute(list(...)))[-1L]
        for (index in seq_along(arguments)) {
          expression <- expressions[[index]]
          if (
            is.call(expression) &&
              identical(expression[[1L]], as.name("::")) &&
              is.function(arguments[[index]])
          ) {
            arguments[[index]] <- structure(
              list(
                package = as.character(expression[[2L]]),
                name = as.character(expression[[3L]])
              ),
              class = "shinyOAuthDB_worker_function"
            )
          }
        }
        arguments <- .odb_task_snapshot(arguments)
        pins <- shiny::isolate(lapply(spec$plans, function(plan) plan$pin()))
        worker <- spec$worker
        worker$user_callback <- is.function(worker$args$user)
        worker$args <- shiny::isolate(.odb_task_snapshot(.odb_task_arguments(
          worker$args
        )))
        worker$allow_demo_http <- identical(
          worker$class,
          ".odb_postgrest_api"
        ) &&
          identical(worker$args$url, "http://127.0.0.1:19444")
        captured_args <- worker$args
        active <<- new.env(parent = emptyenv())
        control <- active
        control$valid <- TRUE
        control$ready <- FALSE
        check <- function(.ready = FALSE) {
          if (.ready) {
            control$ready <- TRUE
          }
          assert_owner()
          if (!control$valid) {
            .odb_abort("The task was cancelled.", "authorization_unavailable")
          }
          for (pin in pins) {
            pin(.check_only = TRUE, .allow_unacquired = !control$ready)
          }
          if (
            !identical(
              .odb_task_snapshot(.odb_task_arguments(spec$worker$args)),
              captured_args
            )
          ) {
            .odb_abort(
              "The connection settings changed.",
              "authorization_unavailable"
            )
          }
          invisible(NULL)
        }
        check()
        valid(check)
        task$invoke(pins, worker, arguments, check)
        invisible(TRUE)
      },
      result = function() {
        assert_owner()
        for (plan in spec$plans) {
          plan$watch()
        }
        check <- valid()
        shiny::req(!is.null(check))
        shiny::req(isTRUE(current(check)))
        value <- task$result()
        shiny::req(!is.null(value))
        if (!isTRUE(value$ok)) {
          stop(value$error)
        }
        value$value
      },
      status = function() {
        assert_owner()
        for (plan in spec$plans) {
          plan$watch()
        }
        check <- valid()
        if (is.null(check) || !isTRUE(current(check))) {
          return("initial")
        }
        status <- task$status()
        if (status != "success") {
          return(status)
        }
        value <- task$result()
        if (is.null(value)) {
          "initial"
        } else if (isTRUE(value$ok)) {
          "success"
        } else {
          "error"
        }
      },
      cancel = function() {
        assert_owner()
        if (!is.null(active)) {
          active$valid <- FALSE
        }
        valid(NULL)
        cancel_worker()
        invisible(NULL)
      }
    ),
    class = "OAuthDBTask"
  )
}

.odb_task_function <- function(value) {
  if (methods::is(value, "genericFunction")) {
    package <- as.character(methods::slot(value, "package"))
    name <- as.character(methods::slot(value, "generic"))
    exported <- tryCatch(getExportedValue(package, name), error = function(e) {
      NULL
    })
    if (identical(value, exported)) {
      return(structure(
        list(package = package, name = name),
        class = "shinyOAuthDB_worker_function"
      ))
    }
  }
  envir <- environment(value)
  if (is.null(envir) || identical(envir, baseenv()) || isNamespace(envir)) {
    metadata <- attributes(value)
    metadata[c("srcref", "wholeSrcref", "srcfile")] <- NULL
    .odb_task_plain(metadata, functions = FALSE)
    attributes(value) <- metadata
    return(value)
  }
  globals <- codetools::findGlobals(value, merge = FALSE)
  if (
    length(setdiff(globals$variables, c(".data", ".env"))) ||
      !all(
        vapply(
          globals$functions,
          exists,
          FALSE,
          envir = baseenv(),
          inherits = FALSE
        )
      )
  ) {
    .odb_abort(
      "Define a self-contained worker function at the top level; pass inputs to invoke() instead of capturing a session."
    )
  }
  # Rebuild without the app environment or source-file attributes.
  eval(parse(text = deparse(value), keep.source = FALSE), envir = baseenv())
}

.odb_task_snapshot <- function(value) {
  if (is.function(value)) {
    return(.odb_task_function(value))
  }
  .odb_task_plain(
    value,
    functions = !(isS4(value) || is.call(value) || is.expression(value))
  )
  .odb_task_plain(attributes(value), functions = FALSE)
  if (is.list(value)) {
    result <- lapply(value, .odb_task_snapshot)
    attributes(result) <- attributes(value)
    return(result)
  }
  value
}

.odb_task_plain <- function(value, functions = TRUE) {
  if (is.function(value)) {
    if (!functions) {
      .odb_abort("Return data from a task, not a function or native handle.")
    }
    .odb_task_function(value)
    return(invisible(NULL))
  } else if (
    is.environment(value) || typeof(value) %in% c("externalptr", "weakref")
  ) {
    .odb_abort(
      "Pass ordinary data to a task, not live connections, clients or environments."
    )
  } else if (isS4(value)) {
    for (name in methods::slotNames(value)) {
      .odb_task_plain(methods::slot(value, name), functions)
    }
  } else if (
    is.list(value) ||
      is.pairlist(value) ||
      is.call(value) ||
      is.expression(value)
  ) {
    items <- as.list(value)
    for (index in seq_along(items)) {
      if (!identical(items[[index]], quote(expr = ))) {
        .odb_task_plain(items[[index]], functions)
      }
    }
  }
  for (item in attributes(value)) {
    .odb_task_plain(item, functions)
  }
  invisible(NULL)
}

.odb_task_arguments <- function(args) {
  if (is.character(args$url) && startsWith(args$url, "http://")) {
    .odb_demo_postgrest_url(args$url)
  }
  if (is.function(args$user)) {
    args["user"] <- list(args$user())
  }
  args
}

.odb_task_callable <- function(value) {
  if (!is.function(value)) {
    return(value)
  }
  namespace <- asNamespace("shinyOAuthDB")
  names <- ls(namespace, pattern = "^\\.odb_", all.names = TRUE)
  matched <- names[vapply(
    names,
    function(name) identical(get(name, namespace), value),
    FALSE
  )]
  if (length(matched)) matched[[1L]] else .odb_task_function(value)
}

.odb_task_source <- function(source) {
  plan <- attr(source, ".odb_task", exact = TRUE)
  if (!is.null(plan)) {
    connect <- .odb_task_callable(plan$connect)
    return(list(
      plans = list(plan),
      worker = list(
        type = "native",
        connect = connect,
        args = plan$args,
        disconnect = .odb_task_callable(plan$disconnect),
        scopes = list(plan$scopes)
      )
    ))
  }
  if (
    !inherits(source, "R6") || !is.environment(source$.__enclos_env__$private)
  ) {
    .odb_abort(
      "source must be a shinyOAuthDB helper or API client; pass con without parentheses."
    )
  }
  private <- source$.__enclos_env__$private
  namespace <- asNamespace("shinyOAuthDB")
  classes <- ls(namespace, pattern = "^\\.odb_", all.names = TRUE)
  classes <- classes[vapply(
    classes,
    function(name) {
      candidate <- get(name, namespace)
      inherits(candidate, "R6ClassGenerator") &&
        identical(candidate$classname, class(source)[[1L]])
    },
    FALSE
  )]
  if (length(classes) != 1L) {
    .odb_abort("This client has no worker factory.")
  }
  connection <- if (exists("connection", private, inherits = FALSE)) {
    private$connection
  } else {
    NULL
  }
  if (!is.null(attr(connection, ".odb_task", exact = TRUE))) {
    spec <- .odb_task_source(connection)
    spec$worker$type <- "wrapped"
    spec$worker$class <- classes
    return(spec)
  }
  if (identical(classes, ".odb_fabric_api")) {
    plans <- lapply(private$providers, function(provider) {
      attr(provider, ".odb_task", exact = TRUE)
    })
    args <- list(groups = private$groups)
    type <- "fabric"
  } else {
    plans <- list(attr(private$provider, ".odb_task", exact = TRUE))
    names <- setdiff(names(formals(source$initialize)), c("provider", "..."))
    args <- stats::setNames(
      lapply(names, function(name) {
        if (!exists(name, private, inherits = FALSE)) {
          .odb_abort("This client's worker settings are unavailable.")
        }
        get(name, private, inherits = FALSE)
      }),
      names
    )
    type <- "http"
  }
  if (!length(plans) || any(vapply(plans, is.null, FALSE))) {
    .odb_abort("This client has no task credential provider.")
  }
  list(
    plans = plans,
    worker = list(
      type = type,
      class = classes,
      args = args,
      scopes = lapply(plans, function(plan) plan$scopes)
    )
  )
}

.odb_task_time <- function() as.numeric(Sys.time())

.odb_task_run <- function(worker, tokens, until, method, arguments) {
  restore <- function(value) {
    if (inherits(value, "shinyOAuthDB_worker_function")) {
      return(getExportedValue(value$package, value$name))
    }
    if (is.list(value)) {
      result <- lapply(value, restore)
      attributes(result) <- attributes(value)
      return(result)
    }
    value
  }
  worker <- restore(worker)
  method <- restore(method)
  arguments <- restore(arguments)
  if (isTRUE(worker$allow_demo_http)) {
    previous <- .odb_demo_http$active
    .odb_demo_http$active <- previous + 1L
    on.exit(
      {
        .odb_demo_http$active <- previous
      },
      add = TRUE
    )
  }
  providers <- lapply(seq_along(tokens), function(index) {
    force(index)
    function(force_refresh = FALSE, scopes = character(), .check_only = FALSE) {
      if (.odb_task_time() >= until[[index]]) {
        .odb_abort(
          "The worker's token lifetime budget expired.",
          "authorization_unavailable"
        )
      }
      if (force_refresh) {
        .odb_abort(
          "A worker cannot refresh its token snapshot; obtain current credentials before another invocation.",
          "refresh_unavailable"
        )
      }
      if (length(setdiff(scopes, worker$scopes[[index]]))) {
        .odb_abort(
          "Declare this operation's required_scopes on the source helper.",
          "insufficient_scope"
        )
      }
      if (.check_only) {
        return(invisible(NULL))
      }
      tokens[[index]]
    }
  })
  for (provider in providers) {
    provider(.check_only = TRUE)
  }
  wrap <- function(token) {
    force(token)
    function() token
  }
  if (worker$type %in% c("native", "wrapped")) {
    connect <- if (is.character(worker$connect)) {
      get(worker$connect, asNamespace("shinyOAuthDB"))
    } else {
      worker$connect
    }
    disconnect <- if (is.character(worker$disconnect)) {
      get(worker$disconnect, asNamespace("shinyOAuthDB"))
    } else {
      worker$disconnect
    }
    opened <- NULL
    if (isTRUE(worker$user_callback)) {
      username <- worker$args$user
      worker$args$user <- function() username
    }
    get_connection <- function() {
      if (is.null(opened)) {
        opened <<- do.call(connect, c(list(providers[[1L]]), worker$args))
      }
      opened
    }
    on.exit(
      tryCatch(
        if (!is.null(opened)) .odb_disconnect(opened, disconnect),
        error = function(error) .odb_cleanup_failure()
      ),
      add = TRUE
    )
    value <- if (worker$type == "native") {
      get_connection()
    } else {
      get(worker$class, asNamespace("shinyOAuthDB"))$new(get_connection)
    }
  } else if (worker$type == "http") {
    value <- do.call(
      get(worker$class, asNamespace("shinyOAuthDB"))$new,
      c(list(provider = wrap(providers[[1L]])), worker$args)
    )
  } else {
    checks <- function() {
      for (provider in providers) {
        provider(.check_only = TRUE)
      }
    }
    read <- function(.pin = FALSE) {
      if (.pin) checks else NULL
    }
    names(providers) <- names(worker$scopes)
    value <- .odb_fabric_api$new(
      read,
      lapply(providers, wrap),
      worker$args$groups
    )
  }
  for (provider in providers) {
    provider(.check_only = TRUE)
  }
  if (is.function(method)) {
    result <- do.call(method, c(list(value), arguments))
  } else if (
    inherits(value, "DBIConnection") && method %in% c("query", "execute")
  ) {
    fun <- if (method == "query") DBI::dbGetQuery else DBI::dbExecute
    result <- do.call(fun, c(list(value), arguments))
  } else if (is.function(value) && method == "call") {
    if (!length(arguments) || !is.function(arguments[[1L]])) {
      .odb_abort("Pass an SDK function to invoke().")
    }
    fun <- arguments[[1L]]
    args <- .odb_api_arguments(fun, arguments[-1L], blocked = "token")
    result <- do.call(fun, c(args, list(token = value)))
  } else {
    fun <- value[[method]]
    if (!is.function(fun)) {
      .odb_abort(paste0("The worker client has no ", method, " method."))
    }
    result <- do.call(fun, arguments)
  }
  if (promises::is.promising(result)) {
    .odb_abort(
      "Worker operations must return data synchronously inside the worker."
    )
  }
  .odb_task_plain(result, functions = FALSE)
  result
}

.odb_task_job <- function(worker, tokens, until, method, arguments) {
  tryCatch(
    list(
      ok = TRUE,
      value = .odb_task_run(worker, tokens, until, method, arguments)
    ),
    error = function(error) {
      message <- conditionMessage(error)
      for (token in tokens) {
        message <- gsub(token, "[REDACTED]", message, fixed = TRUE)
      }
      condition <- errorCondition(
        message,
        class = setdiff(class(error), c("error", "condition"))
      )
      for (name in c(
        "reason",
        "status",
        "service",
        "service_code",
        "request_id"
      )) {
        value <- error[[name]]
        if (
          is.atomic(value) &&
            length(value) == 1L &&
            !is.na(value) &&
            !as.character(value) %in% tokens
        ) {
          if (is.character(value)) {
            for (token in tokens) {
              value <- gsub(token, "[REDACTED]", value, fixed = TRUE)
            }
          }
          condition[[name]] <- value
        }
      }
      list(ok = FALSE, error = condition)
    }
  )
}
