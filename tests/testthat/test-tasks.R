task_test_source <- function(dbname = ":memory:") {
  oauth_db_custom(
    backend = "offline_sqlite", target = "fixture", scopes = "read",
    connect = list(package = "DBI", fun = "dbConnect",
                   driver = list(package = "RSQLite", fun = "SQLite")),
    config = list(dbname = dbname),
    capabilities = list(connector_package = "RSQLite")
  )
}

task_test_handle <- function(source = task_test_source(), acquire = NULL) {
  auth <- shiny::reactiveVal(list(id = "alice", epoch = 1L, scopes = "read"))
  calls <- new.env(parent = emptyenv())
  calls$acquire <- 0L
  handle <- structure(list(
    .source = function() source,
    .capture = function(required_scopes = character()) {
      current <- auth()
      shiny::req(!is.null(current), all(required_scopes %in% current$scopes))
      list(authorization_id = current$id, epoch = current$epoch, source_id = source$id)
    },
    .is_current = function(capture, required_scopes = character()) {
      current <- auth()
      !is.null(current) && identical(capture$authorization_id, current$id) &&
        identical(capture$epoch, current$epoch) &&
        all(required_scopes %in% current$scopes)
    },
    .acquire = function(capture, required_scopes, min_valid_for, async) {
      calls$acquire <- calls$acquire + 1L
      if (is.null(acquire)) return(promises::promise_resolve("fixture-access-token"))
      acquire()
    }
  ), class = "oauth_db_handle")
  list(db = handle, auth = auth, calls = calls)
}

task_test_deferred <- function() {
  state <- new.env(parent = emptyenv())
  state$promise <- promises::promise(function(resolve, reject) {
    state$resolve <- resolve
    state$reject <- reject
  })
  state
}

task_test_drain <- function(session, until = function() TRUE, timeout = 10) {
  deadline <- Sys.time() + timeout
  repeat {
    later::run_now(timeoutSecs = 0.01)
    session$flushReact()
    if (isTRUE(until())) break
    if (Sys.time() >= deadline) stop("Timed out waiting for the task in the test.")
  }
  # Promise settlement uses a few distinct event-loop ticks.
  for (i in seq_len(8L)) {
    later::run_now(timeoutSecs = 0.001)
    session$flushReact()
  }
  invisible(NULL)
}

task_test_context <- function(code) {
  session <- shiny::MockShinySession$new()
  on.exit(session$close(), add = TRUE)
  shiny::withReactiveDomain(session, shiny::isolate(code(session)))
}

test_that("native functions and protected operation arguments are enforced", {
  skip_if_not_installed("mirai")
  task_test_context(function(session) {
    fixture <- task_test_handle()
    expect_error(oauth_db_task(fixture$db, function(...) NULL), "exported|supported|namespace")
    expect_error(oauth_db_task(fixture$db, DBI::dbGetQuery, conn = NULL), "cannot be overridden")
    expect_error(oauth_db_task(fixture$db, DBI::dbGetQuery, pending = "latest"), "effect = 'read'")
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery)
    expect_error(task$invoke(statement = "SELECT 1", host = "other"), "cannot be overridden")
    expect_error(task$invoke(statement = "SELECT 1", TOKEN = "other"), "cannot be overridden")
    expect_error(task$invoke(statement = "SELECT 1", transform = function(x) x), "plain serializable")
    expect_error(task$invoke(statement = "SELECT 1", environment = new.env()), "plain serializable")
    expect_silent(.odb_task_check_plain(list(table = DBI::Id(table = "sales"),
                                           query = DBI::SQL("SELECT 1")), "arguments"))
    expect_equal(fixture$calls$acquire, 0L)
  })
})

test_that("R partial matching cannot bypass protected native Fabric arguments", {
  skip_if_not_installed("mirai")
  skip_if_not_installed("fabricQueryR")
  task_test_context(function(session) {
    dax <- task_test_handle(oauth_db_fabric("dax", workspace_id = "workspace", dataset_id = "model"))
    dax_task <- oauth_db_task(dax$db, fabricQueryR::fabric_pbi_dax_query)
    expect_error(dax_task$invoke(query = "EVALUATE Sales", impersonated_u = "different-user"),
                 "abbreviations cannot match protected")
    graphql <- task_test_handle(oauth_db_fabric("graphql", api = "item"))
    graphql_task <- oauth_db_task(graphql$db, fabricQueryR::fabric_graphql_query)
    expect_error(graphql_task$invoke(query = "{ sales { amount } }", workspa = "different-workspace"),
                 "abbreviations cannot match protected")
    expect_equal(dax$calls$acquire, 0L)
    expect_equal(graphql$calls$acquire, 0L)
    spec <- .odb_operation_spec(task_test_source(), DBI::dbGetQuery)
    expect_silent(.odb_task_check_args(list(statement = "SELECT ?", params = list(1),
                                           immediate = FALSE), spec))
    # A full legitimate native formal can share a prefix with a protected field.
    spec <- .odb_operation_spec(task_test_source(), DBI::dbReadTable)
    spec$protected_args <- c(spec$protected_args, "named_service")
    expect_silent(.odb_task_check_args(list(name = "sales"), spec))
  })
})

test_that("queued work captures authorization and acquires only when it starts", {
  skip_if_not_installed("mirai")
  dispatches <- list()
  work <- task_test_deferred()
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    dispatches[[length(dispatches) + 1L]] <<- payload
    work$promise
  })
  task_test_context(function(session) {
    fixture <- task_test_handle()
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery)
    task$invoke(statement = "SELECT 1")
    task_test_drain(session, until = function() length(dispatches) == 1L)
    task$invoke(statement = "SELECT 2")
    expect_equal(fixture$calls$acquire, 1L)
    fixture$auth(list(id = "bob", epoch = 2L, scopes = "read"))
    work$resolve(.odb_task_outcome(data.frame(value = 1)))
    task_test_drain(session)
    expect_equal(fixture$calls$acquire, 1L)
    expect_length(dispatches, 1L)
    expect_equal(task$status(), "initial")
    expect_error(task$result(), class = "shiny.silent.error")
  })
})

test_that("serial keeps native argument order and invocation defaults replace whole values", {
  skip_if_not_installed("mirai")
  dispatched <- list()
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    dispatched[[length(dispatched) + 1L]] <<- payload$args
    promises::promise_resolve(.odb_task_outcome(payload$args$statement))
  })
  task_test_context(function(session) {
    fixture <- task_test_handle()
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery,
                         statement = "default", params = list(1, 2))
    task$invoke(statement = "first")
    task$invoke(statement = "second", params = list(3))
    task$invoke(statement = "third", params = NULL)
    expect_equal(fixture$calls$acquire, 1L)
    task_test_drain(session, until = function() length(dispatched) == 3L && task$status() == "success")
    expect_equal(vapply(dispatched, `[[`, character(1), "statement"), c("first", "second", "third"))
    expect_equal(dispatched[[1L]]$params, list(1, 2))
    expect_equal(dispatched[[2L]]$params, list(3))
    expect_true("params" %in% names(dispatched[[3L]]))
    expect_null(dispatched[[3L]]$params)
    expect_equal(fixture$calls$acquire, 3L)
    expect_equal(task$result(), "third")
  })
})

test_that("a changed authorization during acquisition cannot launch a worker", {
  skip_if_not_installed("mirai")
  acquisition <- task_test_deferred()
  dispatches <- 0L
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    dispatches <<- dispatches + 1L
    promises::promise_resolve(.odb_task_outcome("unexpected"))
  })
  task_test_context(function(session) {
    fixture <- task_test_handle(acquire = function() acquisition$promise)
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery)
    task$invoke(statement = "SELECT 1")
    expect_equal(task$status(), "running")
    fixture$auth(NULL)
    acquisition$resolve("fixture-access-token")
    task_test_drain(session)
    expect_equal(dispatches, 0L)
    expect_equal(task$status(), "initial")
    expect_error(task$result(), class = "shiny.silent.error")
  })
})

test_that("scope loss hides both successful results and rejected acquisitions", {
  skip_if_not_installed("mirai")
  for (reject in c(FALSE, TRUE)) {
    acquisition <- task_test_deferred()
    local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
      promises::promise_resolve(.odb_task_outcome(data.frame(value = 42)))
    })
    task_test_context(function(session) {
      fixture <- task_test_handle(acquire = function() acquisition$promise)
      task <- oauth_db_task(fixture$db, DBI::dbGetQuery)
      task$invoke(statement = "SELECT 42")
      if (reject) {
        fixture$auth(list(id = "alice", epoch = 1L, scopes = character()))
        acquisition$reject(simpleError("SECRET DRIVER AUTHORIZATION"))
      } else {
        acquisition$resolve("fixture-access-token")
        task_test_drain(session, until = function() task$status() == "success")
        expect_equal(task$result(), data.frame(value = 42))
        fixture$auth(list(id = "alice", epoch = 1L, scopes = character()))
      }
      task_test_drain(session)
      expect_equal(task$status(), "initial")
      expect_error(task$result(), class = "shiny.silent.error")
    })
  }
})

test_that("failures after credential acquisition are caught and redacted", {
  skip_if_not_installed("mirai")
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    stop("SECRET TOKEN=abc DRIVER ERROR", call. = FALSE)
  })
  task_test_context(function(session) {
    fixture <- task_test_handle()
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery)
    task$invoke(statement = "SELECT 1")
    task_test_drain(session, until = function() task$status() == "error")
    error <- tryCatch(task$result(), error = identity)
    expect_s3_class(error, "shinyOAuthDB_task_error")
    expect_false(grepl("SECRET|abc|DRIVER", conditionMessage(error)))
    fixture$auth(NULL)
    expect_equal(task$status(), "initial")
    expect_error(task$result(), class = "shiny.silent.error")
  })
})

test_that("latest and ignore policies do not duplicate background writes", {
  skip_if_not_installed("mirai")
  for (policy in c("latest", "ignore")) {
    first <- task_test_deferred()
    statements <- character()
    local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
      statements <<- c(statements, payload$args$statement)
      if (length(statements) == 1L) return(first$promise)
      promises::promise_resolve(.odb_task_outcome(payload$args$statement))
    })
    task_test_context(function(session) {
      fixture <- task_test_handle()
      task <- oauth_db_task(fixture$db, DBI::dbGetQuery, pending = policy, effect = "read")
      task$invoke(statement = "first")
      task_test_drain(session, until = function() length(statements) == 1L)
      accepted_second <- task$invoke(statement = "second")
      task$invoke(statement = "third")
      expect_identical(accepted_second, policy == "latest")
      expect_equal(fixture$calls$acquire, 1L)
      first$resolve(.odb_task_outcome("first"))
      task_test_drain(session)
      expect_equal(statements, if (policy == "latest") c("first", "third") else "first")
      expect_equal(fixture$calls$acquire, if (policy == "latest") 2L else 1L)
    })
  }
})

test_that("cancel discards waiting work and hides an already submitted result", {
  skip_if_not_installed("mirai")
  work <- task_test_deferred()
  dispatches <- 0L
  local_mocked_bindings(.odb_task_dispatch = function(payload, executor) {
    dispatches <<- dispatches + 1L
    if (dispatches == 1L) work$promise else promises::promise_resolve(.odb_task_outcome("fresh"))
  })
  task_test_context(function(session) {
    fixture <- task_test_handle()
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery)
    task$invoke(statement = "first")
    task_test_drain(session, until = function() dispatches == 1L)
    task$invoke(statement = "waiting")
    task$cancel()
    expect_equal(task$status(), "initial")
    work$resolve(.odb_task_outcome("first"))
    task_test_drain(session)
    expect_equal(dispatches, 1L)
    expect_error(task$result(), class = "shiny.silent.error")
    task$invoke(statement = "fresh")
    task_test_drain(session, until = function() task$status() == "success")
    expect_equal(task$result(), "fresh")
    expect_equal(dispatches, 2L)
  })
})

test_that("tasks cannot be invoked or consumed in another user's session", {
  skip_if_not_installed("mirai")
  owner <- shiny::MockShinySession$new()
  visitor <- shiny::MockShinySession$new()
  on.exit(owner$close(), add = TRUE)
  on.exit(visitor$close(), add = TRUE)
  task <- shiny::withReactiveDomain(owner, shiny::isolate({
    fixture <- task_test_handle()
    oauth_db_task(fixture$db, DBI::dbGetQuery)
  }))
  shiny::withReactiveDomain(visitor, shiny::isolate({
    expect_error(task$invoke(statement = "SELECT 1"), "owning, open Shiny session")
    expect_error(task$status(), "owning, open Shiny session")
    expect_error(task$result(), "owning, open Shiny session")
  }))
})

test_that("native worker closes connections, refuses expired tokens and redacts errors", {
  skip_if_not_installed("RSQLite")
  native <- NULL
  local_mocked_bindings(.odb_adapter_connect = function(source, token_provider) {
    native <<- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    warning("SECRET TOKEN IN DRIVER WARNING", call. = FALSE)
    message("SECRET TOKEN IN DRIVER MESSAGE")
    native
  })
  source <- task_test_source()
  spec <- .odb_operation_spec(source, DBI::dbGetQuery)
  payload <- list(source = source, spec = spec, token = "fixture-access-token",
                  deadline = as.numeric(Sys.time()) + 30,
                  args = list(statement = "SELECT 42 AS value"))
  expect_silent(outcome <- .odb_run_operation(payload))
  expect_null(outcome$error)
  expect_equal(outcome$value, data.frame(value = 42))
  expect_false(DBI::dbIsValid(native))
  payload$args$statement <- "SELECT SECRET_TOKEN FROM nonexistent"
  outcome <- .odb_run_operation(payload)
  expect_equal(outcome$error, "operation")
  expect_false(grepl("SECRET_TOKEN|nonexistent", paste(unlist(outcome), collapse = " ")))
  payload$deadline <- as.numeric(Sys.time()) - 1
  expect_equal(.odb_run_operation(payload)$error, "credential_expired")
})

test_that("Fabric and Databricks DBI workers pass the native provider to the connector", {
  skip_if_not_installed("RSQLite")
  expected_provider <- NULL
  received_provider <- NULL
  local_mocked_bindings(
    .odb_adapter_token_provider = function(source, credential_fun) {
      expected_provider <<- structure(credential_fun, fixture_backend = source$backend)
      expected_provider
    },
    .odb_adapter_connect = function(source, token_provider) {
      received_provider <<- token_provider
      DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    }
  )
  sources <- list(
    oauth_db_fabric_sql("example.datawarehouse.fabric.microsoft.com", "warehouse"),
    oauth_db_databricks("https://example.azuredatabricks.net", warehouse_id = "warehouse")
  )
  for (source in sources) {
    payload <- list(source = source, spec = .odb_operation_spec(source, DBI::dbGetQuery),
                    token = "fixture-access-token", deadline = as.numeric(Sys.time()) + 30,
                    args = list(statement = "SELECT 5 AS value"))
    outcome <- .odb_run_operation(payload)
    expect_null(outcome$error)
    expect_identical(received_provider, expected_provider)
    expect_identical(attr(received_provider, "fixture_backend"), source$backend)
    expect_equal(outcome$value, data.frame(value = 5))
  }
})

test_that("an expired budget hides completion but does not undo an already committed write", {
  skip_if_not_installed("RSQLite")
  clock_calls <- 0L
  local_mocked_bindings(.odb_task_now = function() {
    clock_calls <<- clock_calls + 1L
    # Portable SQLite connect does not use credentials, so the second clock
    # check happens after the native operation has returned.
    if (clock_calls == 1L) 100 else 200
  })
  dbname <- tempfile(fileext = ".sqlite")
  on.exit(unlink(dbname), add = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname)
  DBI::dbExecute(con, "CREATE TABLE writes (value INTEGER)")
  DBI::dbDisconnect(con)
  source <- task_test_source(dbname)
  payload <- list(source = source, spec = .odb_operation_spec(source, DBI::dbExecute),
                  token = "fixture-access-token", deadline = 150,
                  args = list(statement = "INSERT INTO writes (value) VALUES (1)"))
  outcome <- .odb_run_operation(payload)
  expect_equal(outcome$error, "credential_expired")
  expect_null(outcome$value)
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname)
  on.exit(DBI::dbDisconnect(con), add = TRUE, after = FALSE)
  expect_equal(DBI::dbGetQuery(con, "SELECT value FROM writes"), data.frame(value = 1L))
})

test_that("mirai executes a native DBI query while the Shiny process remains responsive", {
  skip_if_not_installed("mirai")
  skip_if_not_installed("RSQLite")
  skip_if(length(find.package("shinyOAuthDB", lib.loc = .libPaths(), quiet = TRUE)) == 0L,
          "Background integration tests require an installed shinyOAuthDB package.")
  mirai::daemons(1)
  on.exit(mirai::daemons(0), add = TRUE)
  task_test_context(function(session) {
    fixture <- task_test_handle()
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery, executor = "mirai")
    task$invoke(statement = "SELECT 42 AS value")
    expect_equal(task$status(), "running")
    responsive <- shiny::reactiveVal(FALSE)
    later::later(function() responsive(TRUE))
    task_test_drain(session, until = function() task$status() %in% c("success", "error"), timeout = 30)
    expect_true(responsive())
    expect_equal(task$result(), data.frame(value = 42))
  })
})

test_that("future executes a native DBI query without changing the app's worker plan", {
  skip_if_not_installed("future")
  skip_if_not_installed("RSQLite")
  skip_if(length(find.package("shinyOAuthDB", lib.loc = .libPaths(), quiet = TRUE)) == 0L,
          "Background integration tests require an installed shinyOAuthDB package.")
  previous <- future::plan(future::multisession, workers = 2)
  on.exit(future::plan(previous), add = TRUE)
  configured <- future::plan()
  task_test_context(function(session) {
    fixture <- task_test_handle()
    task <- oauth_db_task(fixture$db, DBI::dbGetQuery, executor = "future")
    task$invoke(statement = "SELECT 43 AS value")
    expect_equal(task$status(), "running")
    task_test_drain(session, until = function() task$status() %in% c("success", "error"), timeout = 30)
    expect_equal(task$result(), data.frame(value = 43))
    expect_identical(future::plan(), configured)
  })
})

test_that("a real session handle acquires through shinyOAuth and guards a worker outcome", {
  skip_if_not_installed("mirai")
  skip_if_not_installed("RSQLite")
  skip_if(length(find.package("shinyOAuthDB", lib.loc = .libPaths(), quiet = TRUE)) == 0L,
          "Background integration tests require an installed shinyOAuthDB package.")
  mirai::daemons(1)
  on.exit(mirai::daemons(0), add = TRUE)
  odb_test_domain(function(session) {
    fixture <- odb_test_authorization(session, target = "data", unacquired = TRUE)
    auth <- shiny::reactiveVal(fixture$connection)
    source <- oauth_db_custom("offline_sqlite", target = "data", scopes = fixture$scopes[[1L]],
      connect = list(package = "DBI", fun = "dbConnect", driver = list(package = "RSQLite", fun = "SQLite")),
      config = list(dbname = ":memory:"), capabilities = list(connector_package = "RSQLite"))
    db <- oauth_db_session(source, auth)
    task <- oauth_db_task(db, DBI::dbGetQuery, effect = "read")
    expect_identical(db$status()$status, "not_acquired")
    task$invoke(statement = "SELECT 44 AS value")
    task_test_drain(session, until = function() task$status() %in% c("success", "error"), timeout = 30)
    expect_equal(task$result(), data.frame(value = 44))
    expect_equal(fixture$calls$acquire, 1L)
    generation <- db$generation()
    fixture$token(fixture$make_token("fixture-rotated"))
    session$flushReact()
    expect_identical(db$generation(), generation)
    expect_identical(task$status(), "success")
    auth(NULL)
    session$flushReact()
    expect_identical(task$status(), "initial")
    expect_error(task$result(), class = "shiny.silent.error")
  })
})
