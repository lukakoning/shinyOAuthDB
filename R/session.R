#' Bind a data source to a Shiny session's current authorization
#'
#' The handle returns native connections and token providers for existing
#' database packages. Create one handle per source inside `server()` and pass
#' a reactive expression or accessor reading a shinyOAuth module's
#' `connection()` method. Direct pinned connection objects also work.
#' @param source A source created by an `oauth_db_*` constructor.
#' @param authorization A modern shinyOAuth module connection, a custom
#'   object with the [oauth_db_authorization()] interface, or a reactive/no-argument
#'   accessor returning either object or `NULL`. Use `auth$connection()` from
#'   the single module, or `auth$connection(selected_id)` from the multiple
#'   connections module. The selected object must remain pinned to one grant.
#'   An app-login grant is never inferred as a database authorization.
#' @param session The owning Shiny session.
#' @param connection_policy `"session"` reuses a native connection within this
#'   handle and authorization; `"operation"` opens a connection only for scoped
#'   operations. Workers always create their own connections.
#' @param min_valid_for Minimum recorded credential lifetime at use, in seconds.
#' @return A session-owned handle with `connection()`, `token_provider()`,
#'   `generation()`, `status()` and `close()` methods. Logout, observed permission loss and
#'   authorization replacement close cached connections. Ordinary credential
#'   rotation does not invalidate query results; a changed connection credential
#'   can cause reconnection on next use. Direct native calls retain their native
#'   error/reconnect semantics and need application result invalidation. Read
#'   `$generation(required_scopes = ...)` reactively to clear saved data and
#'   errors when their authorization epoch changes. It is a local guard, not a
#'   notification of remote database grant changes.
#' @export
oauth_db_session <- function(source, authorization,
                             session = shiny::getDefaultReactiveDomain(),
                             connection_policy = c("session", "operation"),
                             min_valid_for = 60) {
  if (!inherits(source, "oauth_db_source")) .odb_abort("source must be an oauth_db_source.")
  authorization <- .odb_authorization_reader(authorization)
  connection_policy <- match.arg(connection_policy)
  .odb_seconds(min_valid_for, "min_valid_for", positive = TRUE)
  owner <- .odb_root_session(session)
  if (is.null(owner) || !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain())) ||
      isTRUE(owner$isClosed())) {
    .odb_abort("Create database handles inside their owning Shiny session.", "authorization_unavailable")
  }
  oauth_db_handle$new(source, authorization, owner, connection_policy, min_valid_for)
}

oauth_db_handle <- R6::R6Class(
  "oauth_db_handle", cloneable = FALSE,
  private = list(
    source = NULL, authorization = NULL, owner = NULL, policy = NULL,
    min_valid_for = NULL, ended = FALSE, epoch = 0L, changed = NULL,
    reference = NULL, authorization_id = NULL, native = NULL, selection_required = FALSE,
    credential_hash = NULL, observer = NULL, watches = NULL,
    owned = function() {
      !private$ended && !is.null(private$owner) && !isTRUE(private$owner$isClosed()) &&
        identical(private$owner, .odb_root_session(shiny::getDefaultReactiveDomain()))
    },
    assert_owner = function() {
      if (!private$owned()) .odb_abort("The database handle is unavailable in this session.", "authorization_unavailable")
    },
    close_native = function() {
      native <- private$native
      private$native <- NULL
      private$credential_hash <- NULL
      if (!is.null(native)) tryCatch(.odb_adapter_disconnect(private$source, native), error = function(e) invisible(FALSE))
      invisible(NULL)
    },
    invalidate = function() {
      private$epoch <- private$epoch + 1L
      private$close_native()
      private$changed(private$epoch)
      invisible(NULL)
    },
    current = function() {
      private$assert_owner()
      private$selection_required <- FALSE
      current <- tryCatch(private$authorization(), error = function(e) {
        private$selection_required <- inherits(e, "shinyOAuth_access_error") &&
          identical(e$context$reason, "selection_required")
        NULL
      })
      if (!is.null(current)) {
        .odb_authorization_validate(current)
      }
      id <- if (is.null(current)) NULL else current$id
      if (!identical(id, private$authorization_id) || !identical(current, private$reference)) {
        private$invalidate()
        private$authorization_id <- id
        private$watches <- list()
      }
      private$reference <- current
      if (!is.null(current)) {
        lost <- FALSE
        for (key in names(private$watches)) {
          watch <- private$watches[[key]]
          covered <- private$covered(current, watch$scopes)
          if (isTRUE(watch$covered) && !isTRUE(covered)) lost <- TRUE
          private$watches[[key]]$covered <- isTRUE(covered)
        }
        if (lost) private$invalidate()
      }
      current
    },
    covered = function(current, scopes) {
      tryCatch(.odb_authorization_has_scopes(current, scopes, private$source$auth$target),
        error = function(e) {
          if (inherits(e, c("shinyOAuthDB_invalid_authorization", "shinyOAuthDB_unsupported_authorization_target"))) stop(e)
          FALSE
        })
    },
    watch = function(current, scopes) {
      key <- digest::digest(sort(scopes), algo = "sha256")
      if (is.null(private$watches[[key]])) {
        covered <- private$covered(current, scopes)
        private$watches[[key]] <- list(scopes = scopes, covered = isTRUE(covered))
      }
      invisible(NULL)
    },
    initial_target = function(current) {
      target <- private$source$auth$target
      if (is.null(target)) return(FALSE)
      targets <- .odb_authorization_field(current, "targets")
      if (is.null(targets)) return(FALSE)
      state <- tryCatch(targets()[[target]], error = function(e) NULL)
      identical(state$status, "not_acquired")
    },
    acquire = function(capture, scopes, min_valid_for, force_refresh, async) {
      private$assert_owner()
      current <- private$current()
      if (is.null(current) || !self$.is_current(capture, scopes)) {
        .odb_abort("The operation's authorization is no longer current.", "authorization_unavailable")
      }
      token <- .odb_authorization_call(current, "access_token", list(
        required_scopes = scopes, min_valid_for = min_valid_for,
        force_refresh = force_refresh, async = async, target = private$source$auth$target))
      if (!async && inherits(token, "promise")) {
        .odb_abort("Synchronous access_token() must return a bearer token, not a promise; use async = TRUE for asynchronous acquisition.", "invalid_credential")
      }
      deliver <- function(value) {
        shiny::withReactiveDomain(private$owner, shiny::isolate({
          if (!self$.is_current(capture, scopes)) {
            .odb_abort("The operation's authorization changed during credential acquisition.", "authorization_unavailable")
          }
          .odb_string(value, "access token")
          # Custom providers may attach SDK state to a character value. Only
          # the bearer bytes can leave acquisition, especially for workers.
          attributes(value) <- NULL
          if (grepl("[[:space:]]", value)) .odb_abort("The credential is not a usable bearer token.", "invalid_credential")
          value
        }))
      }
      if (async) return(promises::then(promises::promise_resolve(token), deliver))
      deliver(token)
    },
    provider = function(capture, scopes) {
      .odb_adapter_token_provider(private$source, function(force_refresh = FALSE, async = FALSE) {
        self$.acquire(capture, required_scopes = scopes, min_valid_for = private$min_valid_for,
                      force_refresh = force_refresh, async = async)
      })
    },
    connect = function(capture, scopes, provider) {
      native <- tryCatch(suppressWarnings(suppressMessages(.odb_adapter_connect(private$source, provider))),
        error = function(e) {
          if (!self$.is_current(capture, scopes)) {
            .odb_abort("The authorization changed while opening the connection.", "authorization_unavailable")
          }
          if (inherits(e, c("shinyOAuthDB_error", "shinyOAuth_access_error"))) stop(e)
          .odb_abort("Opening the native database connection failed.", "connection_failure")
        })
      if (!self$.is_current(capture, scopes)) {
        tryCatch(.odb_adapter_disconnect(private$source, native), error = function(e) NULL)
        .odb_abort("The authorization changed while opening the connection.", "authorization_unavailable")
      }
      native
    },
    end = function() {
      if (private$ended) return(invisible(NULL))
      private$invalidate()
      private$ended <- TRUE
      if (!is.null(private$observer)) private$observer$destroy()
      private$reference <- NULL
      private$authorization <- NULL
      private$watches <- list()
      invisible(NULL)
    }
  ),
  public = list(
    initialize = function(source, authorization, owner, policy, min_valid_for) {
      private$source <- source
      private$authorization <- authorization
      private$owner <- owner
      private$policy <- policy
      private$min_valid_for <- min_valid_for
      private$changed <- shiny::reactiveVal(0L)
      private$watches <- list()
      private$observer <- shiny::observe({
        current <- private$current()
        if (!is.null(current)) private$watch(current, private$source$auth$required_scopes)
      }, priority = 100)
      owner$onSessionEnded(private$end)
      invisible(self)
    },
    connection = function(required_scopes = character()) {
      if (!isTRUE(private$source$capabilities$native_dbi)) .odb_abort("This source does not provide a native DBI connection.", "unsupported_operation")
      if (!identical(private$policy, "session")) .odb_abort("Use oauth_db_with_connection() with connection_policy = 'operation'.", "unsupported_operation")
      scopes <- union(private$source$auth$required_scopes, .odb_scopes(required_scopes))
      capture <- self$.capture(scopes)
      token <- self$.acquire(capture, scopes, private$min_valid_for, async = FALSE)
      hash <- digest::digest(token, algo = "sha256")
      valid <- !is.null(private$native) && tryCatch(isTRUE(DBI::dbIsValid(private$native)), error = function(e) FALSE)
      if (valid && identical(hash, private$credential_hash)) return(private$native)
      private$close_native()
      provider <- private$provider(capture, scopes)
      native <- private$connect(capture, scopes, provider)
      private$native <- native
      private$credential_hash <- hash
      native
    },
    token_provider = function(required_scopes = character()) {
      scopes <- union(private$source$auth$required_scopes, .odb_scopes(required_scopes))
      capture <- self$.capture(scopes)
      private$provider(capture, scopes)
    },
    generation = function(required_scopes = character()) {
      if (private$ended) return(private$changed())
      current <- private$current()
      if (!is.null(current)) {
        scopes <- union(private$source$auth$required_scopes, .odb_scopes(required_scopes))
        private$watch(current, scopes)
      }
      private$changed()
    },
    status = function() {
      if (private$ended) return(list(status = "closed", backend = private$source$backend,
        source_id = private$source$id, target = private$source$auth$target, connection_open = FALSE))
      current <- private$current()
      state <- if (private$selection_required) "selection_required" else if (is.null(current)) "waiting_for_authorization" else if (private$initial_target(current)) "not_acquired" else {
        if (private$covered(current, private$source$auth$required_scopes)) "ready" else "needs_authorization"
      }
      list(status = state, backend = private$source$backend, source_id = private$source$id,
           target = private$source$auth$target, connection_open = !is.null(private$native))
    },
    close = function() {
      private$assert_owner()
      private$end()
      invisible(self)
    },
    print = function(...) {
      cat("<oauth_db_handle: ", private$source$backend, "; session-owned; credentials redacted>\n", sep = "")
      invisible(self)
    },
    .source = function() private$source,
    .capture = function(required_scopes = character()) {
      current <- private$current()
      if (private$selection_required) .odb_abort("Several authorizations are available. Select a database connection ID explicitly.", "selection_required")
      if (is.null(current)) .odb_abort("Authorize this source before running an operation.", "authorization_unavailable")
      scopes <- union(private$source$auth$required_scopes, .odb_scopes(required_scopes))
      private$watch(current, scopes)
      list(authorization_id = current$id, epoch = private$epoch, source_id = private$source$id,
           required_scopes = scopes)
    },
    .is_current = function(capture, required_scopes = character()) {
      if (!private$owned()) return(FALSE)
      private$changed()
      current <- private$current()
      if (is.null(current) || !identical(current$id, capture$authorization_id) ||
          !identical(private$epoch, capture$epoch) || !identical(private$source$id, capture$source_id)) return(FALSE)
      scopes <- union(capture$required_scopes, .odb_scopes(required_scopes))
      covered <- private$covered(current, scopes)
      isTRUE(covered) || private$initial_target(current)
    },
    .acquire = function(capture, required_scopes = character(), min_valid_for = 60,
                        force_refresh = FALSE, async = FALSE) {
      .odb_seconds(min_valid_for, "min_valid_for")
      .odb_flag(force_refresh, "force_refresh")
      .odb_flag(async, "async")
      scopes <- union(capture$required_scopes, .odb_scopes(required_scopes))
      private$acquire(capture, scopes, min_valid_for, force_refresh, async)
    },
    .with_connection = function(fun, required_scopes, args) {
      if (!is.function(fun)) .odb_abort("fun must be a function.")
      scopes <- union(private$source$auth$required_scopes, .odb_scopes(required_scopes))
      capture <- self$.capture(scopes)
      if (identical(private$policy, "session")) {
        native <- self$connection(scopes)
      } else {
        self$.acquire(capture, scopes, private$min_valid_for)
        native <- private$connect(capture, scopes, private$provider(capture, scopes))
        on.exit(tryCatch(.odb_adapter_disconnect(private$source, native), error = function(e) NULL), add = TRUE)
      }
      result <- tryCatch(do.call(fun, c(list(native), args)), error = function(e) {
        if (!self$.is_current(capture, scopes)) .odb_abort("The operation's authorization is no longer current.", "invalidated_outcome")
        stop(e)
      })
      if (!self$.is_current(capture, scopes)) .odb_abort("The operation's authorization is no longer current.", "invalidated_outcome")
      .odb_assert_materialized(result)
      result
    }
  )
)

#' Use a native DBI connection within an authorization-checked operation
#' @param db A handle from [oauth_db_session()].
#' @param fun A synchronous function accepting the native connection first.
#' @param ... Explicit arguments passed to `fun`.
#' @param required_scopes Additional configured operation scope requirements.
#' @return A materialized value from `fun`. Native/lazy results cannot leave the
#'   scope. Session policy keeps the connection; operation policy disconnects it.
#' @export
oauth_db_with_connection <- function(db, fun, ..., required_scopes = character()) {
  if (!inherits(db, "oauth_db_handle")) .odb_abort("db must be an oauth_db_session() handle.")
  db$.with_connection(fun, required_scopes, list(...))
}

#' Execute a native DBI query with the handle's connection policy
#' @inheritParams oauth_db_with_connection
#' @param sql SQL statement passed unchanged to DBI.
#' @param params Bound parameter values supported by the native driver.
#' @return The native DBI query result. Use [oauth_db_task()] for nonblocking work.
#' @export
oauth_db_query <- function(db, sql, params = NULL, ..., required_scopes = character()) {
  .odb_string(sql, "sql")
  oauth_db_with_connection(db, DBI::dbGetQuery, statement = sql, params = params,
                           ..., required_scopes = required_scopes)
}

#' Use an existing platform client with an authorization-bound token provider
#' @inheritParams oauth_db_with_connection
#' @param fun A synchronous function accepting a list with `config` and `token`.
#' @return A materialized native platform value.
#' @export
oauth_db_with_client <- function(db, fun, ..., required_scopes = character()) {
  if (!inherits(db, "oauth_db_handle") || !is.function(fun)) .odb_abort("Supply a database handle and callback function.")
  capture <- db$.capture(required_scopes)
  db$.acquire(capture, required_scopes)
  client <- list(config = db$.source()$config, token = db$token_provider(required_scopes))
  result <- tryCatch(fun(client, ...), error = function(e) {
    if (!db$.is_current(capture, required_scopes)) .odb_abort("The operation's authorization is no longer current.", "invalidated_outcome")
    stop(e)
  })
  if (!db$.is_current(capture, required_scopes)) .odb_abort("The operation's authorization is no longer current.", "invalidated_outcome")
  .odb_assert_materialized(result)
  result
}
