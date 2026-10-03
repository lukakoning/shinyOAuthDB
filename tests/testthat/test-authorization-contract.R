contract_test_authorization <- function(id, token_value = paste0("token-", id),
                                         scopes = c("read", "write"), target = NULL,
                                         initial = FALSE) {
  token <- shiny::reactiveVal(token_value)
  permissions <- shiny::reactiveVal(scopes)
  acquired <- shiny::reactiveVal(!initial)
  calls <- new.env(parent = emptyenv())
  calls$access <- list()
  authorization <- list(
    id = id,
    access_token = function(required_scopes = character(), min_valid_for = 60,
                            force_refresh = FALSE, async = FALSE, target = NULL) {
      calls$access[[length(calls$access) + 1L]] <- list(
        required_scopes = required_scopes, min_valid_for = min_valid_for,
        force_refresh = force_refresh, async = async, target = target
      )
      if (!all(required_scopes %in% permissions())) stop("Fixture scope denied.")
      acquired(TRUE)
      if (async) promises::promise_resolve(token()) else token()
    },
    has_scopes = function(scopes, target = NULL) {
      isTRUE(acquired()) && all(scopes %in% permissions())
    }
  )
  if (!is.null(target)) authorization$targets <- function() {
    stats::setNames(list(list(status = if (acquired()) "active" else "not_acquired")), target)
  }
  list(authorization = authorization, token = token, permissions = permissions,
       acquired = acquired, calls = calls)
}

contract_test_drain <- function(session, until = function() TRUE, timeout = 5) {
  deadline <- Sys.time() + timeout
  repeat {
    later::run_now(timeoutSecs = 0.01)
    session$flushReact()
    if (isTRUE(until())) break
    if (Sys.time() >= deadline) stop("Timed out waiting for a custom authorization test.")
  }
  for (tick in seq_len(8L)) {
    later::run_now(timeoutSecs = 0.001)
    session$flushReact()
  }
  invisible(NULL)
}

test_that("custom authorization objects work directly, reactively and through an accessor", {
  skip_if_not_installed("RSQLite")
  for (input_form in c("direct", "reactive", "accessor")) {
    odb_test_domain(function(session) {
      fixture <- contract_test_authorization(input_form)
      authorization <- switch(input_form,
        direct = fixture$authorization,
        reactive = shiny::reactive(fixture$authorization),
        accessor = function() fixture$authorization)
      db <- oauth_db_session(odb_test_source(), authorization)
      con <- db$connection()
      expect_s4_class(con, "DBIConnection")
      expect_identical(db$connection(), con)
      expect_identical(db$token_provider()(), paste0("token-", input_form))
      expect_equal(DBI::dbGetQuery(con, "SELECT 7 AS value"), data.frame(value = 7L))
    })
  }
})

test_that("authorization contract does not require a particular class or list representation", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    fixture <- contract_test_authorization("environment")
    authorization <- list2env(fixture$authorization, parent = emptyenv())
    db <- oauth_db_session(odb_test_source(), authorization)
    expect_identical(db$token_provider()(), "token-environment")
    expect_equal(oauth_db_query(db, "SELECT 8 AS value"), data.frame(value = 8L))
  })
})

test_that("accessors with optional arguments and dots are callable without supplying inputs", {
  odb_test_domain(function(session) {
    fixture <- contract_test_authorization("variadic-accessor")
    accessors <- list(
      function(...) fixture$authorization,
      function(option = NULL, ...) fixture$authorization
    )
    for (accessor in accessors) {
      db <- oauth_db_session(odb_test_source(), accessor)
      expect_identical(db$token_provider()(), "token-variadic-accessor")
    }
    expect_error(oauth_db_session(odb_test_source(), function(required) fixture$authorization),
                 class = "shinyOAuthDB_invalid_authorization")
  })
})

test_that("public custom adapter forwards scope, lifetime, refresh and async requests", {
  odb_test_domain(function(session) {
    fixture <- contract_test_authorization("wrapped", target = "data")
    authorization <- oauth_db_authorization(
      id = fixture$authorization$id,
      access_token = fixture$authorization$access_token,
      has_scopes = fixture$authorization$has_scopes,
      targets = fixture$authorization$targets
    )
    db <- oauth_db_session(odb_test_source(target = "data"), authorization,
                           min_valid_for = 75)
    expect_true(authorization$has_scopes("read", target = "data"))
    expect_identical(db$token_provider()(force_refresh = TRUE), "token-wrapped")
    forwarded <- fixture$calls$access[[1L]]
    expect_identical(forwarded$required_scopes, "read")
    expect_identical(forwarded$min_valid_for, 75)
    expect_true(forwarded$force_refresh)
    expect_false(forwarded$async)
    expect_identical(forwarded$target, "data")
    capture <- db$.capture()
    promise <- db$.acquire(capture, required_scopes = "write", min_valid_for = 90,
                           force_refresh = TRUE, async = TRUE)
    expect_s3_class(promise, "promise")
    value <- NULL
    promises::then(promise, function(token) value <<- token)
    contract_test_drain(session, until = function() !is.null(value))
    expect_identical(value, "token-wrapped")
    forwarded <- fixture$calls$access[[2L]]
    expect_setequal(forwarded$required_scopes, c("read", "write"))
    expect_identical(forwarded$min_valid_for, 90)
    expect_true(forwarded$force_refresh)
    expect_true(forwarded$async)
    expect_identical(forwarded$target, "data")
  })
})

test_that("synchronous promise responses are rejected before entering a native connector", {
  for (wrapped in c(FALSE, TRUE)) {
    odb_test_domain(function(session) {
      entered_connector <- 0L
      access <- function(required_scopes, min_valid_for, force_refresh, async, target = NULL) {
        promises::promise_resolve("promise-fixture-token")
      }
      scopes <- function(scopes, target = NULL) TRUE
      authorization <- if (wrapped) oauth_db_authorization("sync-promise", access, scopes) else {
        list(id = "sync-promise", access_token = access, has_scopes = scopes)
      }
      source <- odb_test_source(on_connect = function(token) {
        entered_connector <<- entered_connector + 1L
      })
      db <- oauth_db_session(source, authorization)
      expect_error(db$connection(), "promise|async|synchronous", ignore.case = TRUE)
      expect_equal(entered_connector, 0L)
      if (wrapped) {
        expect_error(authorization$access_token(), "promise|async|synchronous", ignore.case = TRUE)
      }
    })
  }
})

test_that("cached scalar credentials normalize to a promise for asynchronous acquisition", {
  for (wrapped in c(FALSE, TRUE)) {
    odb_test_domain(function(session) {
      access <- function(required_scopes, min_valid_for, force_refresh, async, target = NULL) {
        "cached-scalar-fixture-token"
      }
      scopes <- function(scopes, target = NULL) TRUE
      authorization <- if (wrapped) oauth_db_authorization("scalar-cache", access, scopes) else {
        list(id = "scalar-cache", access_token = access, has_scopes = scopes)
      }
      db <- oauth_db_session(odb_test_source(), authorization)
      promise <- db$.acquire(db$.capture(), async = TRUE)
      expect_s3_class(promise, "promise")
      value <- NULL
      promises::then(promise, function(token) value <<- token)
      contract_test_drain(session, until = function() !is.null(value))
      expect_identical(value, "cached-scalar-fixture-token")
    })
  }
})

test_that("callbacks without a target parameter support only untargeted authorizations", {
  odb_test_domain(function(session) {
    calls <- 0L
    access <- function(required_scopes, min_valid_for, force_refresh, async) {
      calls <<- calls + 1L
      if (async) promises::promise_resolve("untargeted-token") else "untargeted-token"
    }
    scopes <- function(scopes) all(scopes %in% c("read", "write"))
    authorization <- oauth_db_authorization("untargeted", access, scopes)
    db <- oauth_db_session(odb_test_source(), authorization)
    expect_identical(db$token_provider()(), "untargeted-token")
    expect_true(authorization$has_scopes("read"))
    expect_error(authorization$access_token(required_scopes = "read", target = "data"),
                 "target", ignore.case = TRUE)
    expect_error(authorization$has_scopes("read", target = "data"),
                 "target", ignore.case = TRUE)
    expect_equal(calls, 1L)
    # Direct duck-typed objects receive the same compatibility protection.
    plain <- list(id = "plain-untargeted", access_token = access, has_scopes = scopes)
    direct <- oauth_db_session(odb_test_source(), plain)
    expect_identical(direct$token_provider()(), "untargeted-token")
    named <- oauth_db_session(odb_test_source(target = "data"), plain)
    expect_error(named$token_provider()(), "target|authorization", ignore.case = TRUE)
    expect_equal(calls, 2L)
    # Permission support alone cannot make an untargeted credential callback
    # safe for a named resource: the token accessor must support it too.
    plain$has_scopes <- function(scopes, target = NULL) TRUE
    named <- oauth_db_session(odb_test_source(target = "data"), plain)
    expect_error(named$token_provider()(), "target", ignore.case = TRUE)
    expect_equal(calls, 2L)
  })
})

test_that("selecting database grants never falls back to a separate application login", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    app_login <- contract_test_authorization("application-login")
    sales <- contract_test_authorization("sales-grant")
    warehouse <- contract_test_authorization("warehouse-grant")
    grants <- list(sales = sales$authorization, warehouse = warehouse$authorization)
    selection <- shiny::reactiveVal("sales")
    db <- oauth_db_session(odb_test_source(), function() {
      selected <- selection()
      if (is.null(selected)) NULL else grants[[selected]]
    })
    first <- db$connection()
    retained_sales_provider <- db$token_provider()
    epoch <- db$generation()
    app_login$token("application-login-rotated")
    session$flushReact()
    expect_identical(db$generation(), epoch)
    expect_identical(db$connection(), first)
    expect_identical(retained_sales_provider(), "token-sales-grant")
    selection("warehouse")
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    expect_gt(db$generation(), epoch)
    expect_error(retained_sales_provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(db$token_provider()(), "token-warehouse-grant")
    selection(NULL)
    session$flushReact()
    expect_identical(db$status()$status, "waiting_for_authorization")
    expect_error(db$token_provider(), class = "shinyOAuthDB_authorization_unavailable")
    selection("sales")
    session$flushReact()
    expect_identical(db$token_provider()(), "token-sales-grant")
    expect_error(retained_sales_provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_length(app_login$calls$access, 0L)
  })
})

test_that("independent handles retain their explicitly selected custom grants", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    first <- contract_test_authorization("first")
    second <- contract_test_authorization("second")
    db_first <- oauth_db_session(odb_test_source(), first$authorization)
    db_second <- oauth_db_session(odb_test_source(), second$authorization)
    first_con <- db_first$connection()
    second_con <- db_second$connection()
    expect_false(identical(first_con, second_con))
    expect_identical(db_first$token_provider()(), "token-first")
    expect_identical(db_second$token_provider()(), "token-second")
    second_epoch <- db_second$generation()
    first$permissions(character())
    session$flushReact()
    expect_false(DBI::dbIsValid(first_con))
    expect_true(DBI::dbIsValid(second_con))
    expect_identical(db_second$generation(), second_epoch)
    expect_error(db_first$token_provider()(), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(db_second$connection(), second_con)
  })
})

test_that("a replacement reference cannot reuse a retained provider merely by repeating its ID", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    original <- contract_test_authorization("repeated-id", token_value = "original-grant-token")
    replacement <- contract_test_authorization("repeated-id", token_value = "replacement-grant-token")
    selected <- shiny::reactiveVal(original$authorization)
    db <- oauth_db_session(odb_test_source(), selected)
    con <- db$connection()
    provider <- db$token_provider()
    epoch <- db$generation()
    selected(replacement$authorization)
    session$flushReact()
    expect_gt(db$generation(), epoch)
    expect_false(DBI::dbIsValid(con))
    expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(db$token_provider()(), "replacement-grant-token")
  })
})

test_that("an ambiguous manager selection reports the public reason and never chooses the first grant", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    first <- contract_test_authorization("manager-first")
    second <- contract_test_authorization("manager-second")
    choices <- list(first = first$authorization, second = second$authorization)
    selection <- shiny::reactiveVal(NULL)
    accessor <- function() {
      selected <- selection()
      if (is.null(selected)) {
        stop(structure(
          list(message = "Several authorizations are available.", call = NULL,
               context = list(reason = "selection_required")),
          class = c("shinyOAuth_access_error", "error", "condition")
        ))
      }
      choices[[selected]]
    }
    db <- oauth_db_session(odb_test_source(), accessor)
    expect_identical(db$status()$status, "selection_required")
    expect_error(db$token_provider(), class = "shinyOAuthDB_selection_required")
    expect_length(first$calls$access, 0L)
    expect_length(second$calls$access, 0L)
    selection("second")
    session$flushReact()
    expect_identical(db$status()$status, "ready")
    con <- db$connection()
    provider <- db$token_provider()
    expect_identical(provider(), "token-manager-second")
    selection(NULL)
    session$flushReact()
    expect_false(DBI::dbIsValid(con))
    expect_identical(db$status()$status, "selection_required")
    expect_error(db$connection(), class = "shinyOAuthDB_selection_required")
    expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_length(first$calls$access, 0L)
  })
})

test_that("custom permission state is reactive and token rotation keeps authorization identity", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    fixture <- contract_test_authorization("stable")
    db <- oauth_db_session(odb_test_source(), fixture$authorization)
    first <- db$connection()
    provider <- db$token_provider()
    epoch <- db$generation(required_scopes = "write")
    fixture$token("same-grant-new-token")
    session$flushReact()
    expect_identical(db$generation(), epoch)
    expect_identical(provider(), "same-grant-new-token")
    rotated <- db$connection()
    expect_false(DBI::dbIsValid(first))
    fixture$permissions("read")
    session$flushReact()
    expect_gt(db$generation(), epoch)
    expect_false(DBI::dbIsValid(rotated))
    expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(db$token_provider()(), "same-grant-new-token")
  })
})

test_that("custom first-target metadata permits acquisition without pretending consent is known", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    fixture <- contract_test_authorization("first-target", target = "data", initial = TRUE)
    authorization <- oauth_db_authorization(
      fixture$authorization$id, fixture$authorization$access_token,
      fixture$authorization$has_scopes, targets = fixture$authorization$targets)
    db <- oauth_db_session(odb_test_source(target = "data"), authorization)
    expect_identical(db$status()$status, "not_acquired")
    before <- db$generation()
    expect_silent(db$connection())
    session$flushReact()
    expect_identical(db$status()$status, "ready")
    expect_identical(db$generation(), before)
    expect_identical(fixture$calls$access[[1L]]$target, "data")
  })
})

test_that("non-scalar or non-logical custom permission evidence fails closed", {
  odb_test_domain(function(session) {
    for (evidence in list(NA, 1L, "TRUE", c(TRUE, FALSE), logical())) {
      calls <- 0L
      authorization <- list(id = "invalid-evidence",
        access_token = function(required_scopes, min_valid_for, force_refresh, async, target = NULL) {
          calls <<- calls + 1L
          "must-not-be-used"
        },
        has_scopes = function(scopes, target = NULL) evidence)
      db <- oauth_db_session(odb_test_source(), authorization)
      expect_error(db$token_provider()(), class = "shinyOAuthDB_error")
      expect_equal(calls, 0L)
    }
  })
})

test_that("custom auth selection changed during async acquisition cannot submit old credentials", {
  skip_if_not_installed("mirai")
  deferred <- new.env(parent = emptyenv())
  promise <- promises::promise(function(resolve, reject) deferred$resolve <- resolve)
  dispatches <- 0L
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    dispatches <<- dispatches + 1L
    promises::promise_resolve(.odb_task_outcome("unexpected"))
  })
  odb_test_domain(function(session) {
    first <- contract_test_authorization("async-first")
    first$authorization$access_token <- function(required_scopes, min_valid_for,
                                                force_refresh, async, target = NULL) promise
    second <- contract_test_authorization("async-second")
    selection <- shiny::reactiveVal(first$authorization)
    source <- oauth_db_custom("contract_worker", scopes = "read",
      connect = list(package = "DBI", fun = "dbConnect",
                     driver = list(package = "RSQLite", fun = "SQLite")),
      config = list(dbname = ":memory:"), capabilities = list(connector_package = "RSQLite"))
    db <- oauth_db_session(source, function() selection())
    task <- oauth_db_task(db, DBI::dbGetQuery)
    task$invoke(statement = "SELECT 1")
    expect_identical(task$status(), "running")
    selection(second$authorization)
    deferred$resolve("old-selection-secret-token")
    expect_silent(contract_test_drain(session))
    expect_equal(dispatches, 0L)
    expect_identical(task$status(), "initial")
    expect_error(task$result(), class = "shiny.silent.error")
  })
})

test_that("real mirai tasks use custom authorization while exporting only fixed worker data", {
  skip_if_not_installed("mirai")
  skip_if_not_installed("RSQLite")
  skip_if(length(find.package("shinyOAuthDB", lib.loc = .libPaths(), quiet = TRUE)) == 0L,
          "Background integration tests require an installed shinyOAuthDB package.")
  mirai::daemons(1)
  on.exit(mirai::daemons(0), add = TRUE)
  original_dispatch <- .odb_task_dispatch
  captured_payload <- NULL
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    captured_payload <<- payload
    original_dispatch(payload, executor)
  })
  odb_test_domain(function(session) {
    private_framework_state <- new.env(parent = emptyenv())
    private_framework_state$refresh_token <- "custom-fixture-refresh-secret"
    private_framework_state$client_secret <- "custom-fixture-client-secret"
    permissions <- shiny::reactiveVal("read")
    callback_count <- 0L
    authorization <- oauth_db_authorization("custom-worker-grant",
      access_token = function(required_scopes, min_valid_for, force_refresh, async) {
        # These values belong to the authentication framework and remain in
        # the main Shiny process, despite being captured by the callback.
        stopifnot(nzchar(private_framework_state$refresh_token),
                  nzchar(private_framework_state$client_secret))
        callback_count <<- callback_count + 1L
        if (!all(required_scopes %in% permissions())) stop("Scope denied.")
        if (async) promises::promise_resolve("custom-worker-access-token") else "custom-worker-access-token"
      },
      has_scopes = function(scopes) all(scopes %in% permissions())
    )
    source <- oauth_db_custom("custom_worker_fixture", scopes = "read",
      connect = list(package = "DBI", fun = "dbConnect",
                     driver = list(package = "RSQLite", fun = "SQLite")),
      config = list(dbname = ":memory:"), capabilities = list(connector_package = "RSQLite"))
    db <- oauth_db_session(source, authorization)
    task <- oauth_db_task(db, DBI::dbGetQuery, executor = "mirai")
    task$invoke(statement = "SELECT 73 AS value")
    expect_identical(task$status(), "running")
    contract_test_drain(session,
      until = function() task$status() %in% c("success", "error"), timeout = 30)
    expect_equal(task$result(), data.frame(value = 73L))
    expect_equal(callback_count, 1L)
    expect_identical(captured_payload$token, "custom-worker-access-token")
    expect_identical(captured_payload$capture$authorization_id, "custom-worker-grant")
    expect_silent(.odb_task_check_plain(captured_payload, "worker payload"))
    expect_false(any(c("authorization", "session", "client", "provider") %in% names(captured_payload)))
    encoded <- rawToChar(serialize(captured_payload, NULL, ascii = TRUE))
    expect_false(grepl(private_framework_state$refresh_token, encoded, fixed = TRUE))
    expect_false(grepl(private_framework_state$client_secret, encoded, fixed = TRUE))
  })
})

test_that("custom authorization handles enforce Shiny session ownership", {
  odb_test_domain(function(session) {
    fixture <- contract_test_authorization("owned")
    db <- oauth_db_session(odb_test_source(), fixture$authorization)
    provider <- db$token_provider()
    other <- shiny::MockShinySession$new()
    on.exit(other$close(), add = TRUE)
    shiny::withReactiveDomain(other, shiny::isolate({
      expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
      expect_error(db$token_provider(), class = "shinyOAuthDB_authorization_unavailable")
    }))
    expect_length(fixture$calls$access, 0L)
    db$close()
    expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_length(fixture$calls$access, 0L)
  })
})
