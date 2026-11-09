test_that("tasks reject an installed mirai below the supported version", {
  skip_if_not_installed("mirai")
  local_mocked_bindings(
    packageVersion = function(package) package_version("2.5.0"),
    .package = "utils"
  )
  expect_error(
    oauth_db_task(NULL),
    "mirai >= 2.5.1",
    class = "shinyOAuthDB_missing_dependency",
    fixed = TRUE
  )
})

test_that("database tasks acquire asynchronously and preserve result authorization", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, "A", "read")
    b <- odb_test_authorization(session, "B", "read")
    selected <- shiny::reactiveVal(a$connection)
    source <- oauth_db_connect(
      selected,
      connect = task_sqlite_connect,
      required_scopes = "read"
    )
    rows <- oauth_db_task(source)
    expect_s3_class(rows, "OAuthDBTask")
    expect_identical(rows$status(), "initial")
    expect_error(rows$result(), class = "shiny.silent.error")
    expect_true(rows$invoke("SELECT * FROM identity"))
    task_flush()
    expect_identical(rows$status(), "running")
    expect_false(rows$invoke("SELECT 'must-not-run'"))
    expect_length(calls$pending, 1L)
    worker <- calls$pending[[1L]]
    expect_identical(worker$arguments$tokens, list("fixture-A"))
    expect_false(any(
      c("pin", "owner", "authorization") %in% names(worker$arguments$worker)
    ))
    worker$resolve(worker$run())
    task_flush()
    expect_identical(rows$result()$token, "fixture-A")
    a$token(a$make_token("rotated"))
    session$flushReact()
    expect_identical(rows$result()$token, "fixture-A")
    selected(b$connection)
    session$flushReact()
    expect_error(rows$result(), class = "shiny.silent.error")
    selected(a$connection)
    session$flushReact()
    expect_error(rows$result(), class = "shiny.silent.error")
    expect_true(rows$invoke("SELECT * FROM identity"))
    task_flush()
    worker <- calls$pending[[2L]]
    worker$resolve(worker$run())
    task_flush()
    expect_identical(rows$result()$token, "rotated")
    a$token(a$make_token("denied", "other"))
    session$flushReact()
    expect_error(rows$result(), class = "shiny.silent.error")
    a$token(a$make_token("restored"))
    session$flushReact()
    expect_error(rows$result(), class = "shiny.silent.error")
  })
})

test_that("pending tasks cancel on permission loss and never publish late results", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "read")
    source <- oauth_db_connect(
      auth$connection,
      connect = task_sqlite_connect,
      required_scopes = "read"
    )
    rows <- oauth_db_task(source)
    rows$invoke("SELECT * FROM identity")
    task_flush()
    worker <- calls$pending[[1L]]
    value <- worker$run()
    auth$token(auth$make_token("denied", "other"))
    session$flushReact()
    expect_equal(calls$stopped, 1L)
    auth$token(auth$make_token("restored"))
    session$flushReact()
    worker$resolve(value)
    task_flush()
    expect_error(rows$result(), class = "shiny.silent.error")
  })
})

test_that("manual cancellation hides results and does not replay operations", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    rows <- oauth_db_task(oauth_db_connect(
      auth$connection,
      connect = task_sqlite_connect
    ))
    rows$invoke("SELECT * FROM identity")
    task_flush()
    rows$cancel()
    expect_equal(calls$stopped, 1L)
    calls$pending[[1L]]$resolve(data.frame(value = "late"))
    task_flush()
    expect_error(rows$result(), class = "shiny.silent.error")
    expect_length(calls$pending, 1L)
    rows$invoke("SELECT * FROM identity")
    task_flush()
    expect_length(calls$pending, 2L)
  })
})

test_that("workers close native connections on success, errors and rejected handles", {
  skip_if_not_installed("RSQLite")
  for (method in list(
    "query",
    function(con) stop("Native failure"),
    function(con) con
  )) {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    worker <- list(
      type = "native",
      connect = function(token) con,
      args = list(),
      disconnect = NULL,
      scopes = list(character())
    )
    if (identical(method, "query")) {
      expect_equal(
        .odb_task_run(
          worker,
          list("fixture"),
          Inf,
          method,
          list("SELECT 1 AS value")
        )$value,
        1
      )
    } else {
      expect_error(.odb_task_run(worker, list("fixture"), Inf, method, list()))
    }
    expect_false(DBI::dbIsValid(con))
  }
})

test_that("worker credentials cannot refresh or exceed their declared permissions", {
  worker <- list(type = "native", args = list(), scopes = list("read"))
  worker$connect <- function(token) token(force_refresh = TRUE)
  expect_error(
    .odb_task_run(worker, list("fixture"), Inf, "query", list()),
    class = "shinyOAuthDB_refresh_unavailable"
  )
  worker$connect <- function(token) token(scopes = "write")
  expect_error(
    .odb_task_run(worker, list("fixture"), Inf, "query", list()),
    class = "shinyOAuthDB_insufficient_scope"
  )
  worker$connect <- function(token) stop("must not connect")
  expect_error(
    .odb_task_run(worker, list("fixture"), 0, "query", list()),
    class = "shinyOAuthDB_authorization_unavailable"
  )
})

test_that("HTTP task factories preserve backend configuration", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(
      auth$connection,
      "https://data.example/rest/v1",
      schema = "reporting",
      timeout = 17
    )
    spec <- .odb_task_source(api)
    expect_identical(spec$worker$class, ".odb_postgrest_api")
    expect_identical(spec$worker$args$url, "https://data.example/rest/v1")
    expect_identical(spec$worker$args$schema, "reporting")
    expect_identical(spec$worker$args$timeout, 17)
    httr2::local_mocked_responses(function(req) {
      expect_identical(
        httr2::req_get_headers(req, redacted = "reveal")$Authorization,
        "Bearer fixture"
      )
      expect_identical(
        httr2::req_get_headers(req)[["Accept-Profile"]],
        "reporting"
      )
      odb_http_response('[{"id":1}]')
    })
    result <- .odb_task_run(
      spec$worker,
      list("fixture"),
      Inf,
      "select",
      list("orders", limit = 20L)
    )
    expect_equal(result$id, 1)
  })
})

test_that("all HTTP clients expose serializable worker configuration", {
  constructors <- list(
    function(auth) oauth_db_bigquery_api(auth, "project"),
    function(auth) {
      oauth_db_cosmos_api(
        auth,
        "https://example.documents.azure.com",
        "db",
        "items"
      )
    },
    function(auth) oauth_db_clickhouse_api(auth, "https://data.example"),
    function(auth) oauth_db_cratedb_api(auth, "https://data.example"),
    function(auth) oauth_db_databricks_api(auth, "workspace.example"),
    function(auth) oauth_db_elasticsearch_api(auth, "https://data.example"),
    function(auth) oauth_db_libsql_api(auth, "https://data.example"),
    function(auth) oauth_db_neo4j_api(auth, "https://data.example"),
    function(auth) oauth_db_opensearch_api(auth, "https://data.example"),
    function(auth) oauth_db_oracle_ords_api(auth, "https://data.example"),
    function(auth) {
      oauth_db_salesforce_api(auth, "https://org.my.salesforce.com")
    },
    function(auth) {
      oauth_db_salesforce_data_cloud_api(auth, "https://org.my.salesforce.com")
    },
    function(auth) {
      oauth_db_supabase_api(
        auth,
        "https://project.supabase.co",
        "sb_publishable_fixture"
      )
    }
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (constructor in constructors) {
      api <- constructor(auth$connection)
      spec <- .odb_task_source(api)
      expect_length(spec$plans, 1L)
      expect_silent(.odb_task_plain(spec$worker$args))
      expect_identical(unserialize(serialize(spec$worker, NULL)), spec$worker)
    }
  })
})

test_that("Fabric tasks recreate scoped token callbacks in the worker", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(
      session,
      services = c("fabric", "kql")
    )
    api <- oauth_db_fabric_api(
      auth$connection,
      targets = c(fabric = "fabric", kql = "kql")
    )
    spec <- .odb_task_source(api)
    expect_length(spec$plans, 2L)
    fun <- eval(
      quote(function(token) {
        c(
          token("https://api.fabric.microsoft.com/.default"),
          token("https://api.kusto.windows.net/.default")
        )
      }),
      globalenv()
    )
    result <- .odb_task_run(
      spec$worker,
      list("fabric-token", "kql-token"),
      c(Inf, Inf),
      "call",
      list(fun)
    )
    expect_identical(result, c("fabric-token", "kql-token"))
  })
})

test_that("tasks reject captured sessions and native handles before dispatch", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    source <- oauth_db_connect(auth$connection, connect = task_sqlite_connect)
    expect_error(
      oauth_db_task(source, method = function(con) session),
      "top level"
    )
    rows <- oauth_db_task(source)
    expect_error(rows$invoke(session), "ordinary data")
    expect_error(
      rows$invoke(as.call(list(as.name("list"), session))),
      "ordinary data"
    )
    expect_length(calls$pending, 0L)
  })
})

test_that("self-contained app functions are detached from their surrounding environment", {
  app <- new.env(parent = globalenv())
  app$private_marker <- "must-not-be-serialized-with-the-job"
  fun <- eval(
    quote(function(connection) {
      DBI::dbGetQuery(connection, "SELECT 1")
    }),
    app
  )
  detached <- .odb_task_function(fun)
  expect_identical(environment(detached), baseenv())
  expect_false(grepl(
    app$private_marker,
    rawToChar(serialize(detached, NULL, ascii = TRUE)),
    fixed = TRUE
  ))
  captured <- eval(quote(function(connection) private_marker), app)
  expect_error(.odb_task_function(captured), "self-contained", fixed = TRUE)
})

test_that("asynchronous credential acquisition is guarded before worker dispatch", {
  skip_if_not_installed("mirai", "2.5.1")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    resolve_token <- NULL
    grant <- list(
      id = "A",
      has_scopes = function(...) TRUE,
      access_token = function(async, min_valid_for_seconds, ...) {
        expect_true(async)
        expect_equal(min_valid_for_seconds, 120)
        promises::promise(function(resolve, reject) {
          resolve_token <<- resolve
        })
      }
    )
    selected <- shiny::reactiveVal(grant)
    source <- oauth_db_connect(selected, connect = task_sqlite_connect)
    rows <- oauth_db_task(source)
    rows$invoke("SELECT * FROM identity")
    task_flush()
    expect_identical(rows$status(), "running")
    selected(NULL)
    session$flushReact()
    selected(grant)
    session$flushReact()
    resolve_token("fixture-A")
    task_flush()
    expect_length(calls$pending, 0L)
    expect_error(rows$result(), class = "shiny.silent.error")
  })
})

test_that("real worker queries keep their owning Shiny session responsive", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  skip_if(mirai::daemons_set(), "Preserve an existing worker pool")
  mirai::daemons(1)
  withr::defer(mirai::daemons(0))
  paths <- .libPaths()
  package_path <- system.file(package = "shinyOAuthDB")
  mirai::everywhere(
    {
      .libPaths(paths)
      if (!file.exists(file.path(package_path, "Meta", "package.rds"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(shinyOAuthDB)
      }
    },
    paths = paths,
    package_path = package_path
  )
  calls <- new.env(parent = emptyenv())
  fetch <- eval(
    quote(function(connection, delay) {
      Sys.sleep(delay)
      DBI::dbGetQuery(connection, "SELECT * FROM identity")
    }),
    globalenv()
  )
  server <- function(input, output, session) {
    auth <- odb_test_authorization(session)
    source <- oauth_db_connect(auth$connection, connect = task_sqlite_connect)
    rows <- oauth_db_task(source, method = fetch)
    shiny::observeEvent(input$ping, {
      calls$ping <- input$ping
    })
    output$rows <- shiny::renderTable(rows$result())
  }
  shiny::testServer(server, {
    rows$invoke(1)
    task_flush()
    expect_identical(rows$status(), "running")
    session$setInputs(ping = 1L)
    expect_identical(calls$ping, 1L)
    expect_error(output$rows, class = "shiny.silent.error")
    deadline <- proc.time()[["elapsed"]] + 30
    while (rows$status() == "running" && proc.time()[["elapsed"]] < deadline) {
      later::run_now(0.01)
      session$flushReact()
    }
    expect_identical(rows$status(), "success")
    expect_identical(rows$result()$token, "fixture-A")
    expect_false(identical(rows$result()$pid, Sys.getpid()))
  })
})

test_that("cached rendered results clear when authorization changes", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  task_app_workers()
  state <- new.env(parent = emptyenv())
  server <- function(input, output, session) {
    state$a <- odb_test_authorization(session, "A", "read")
    state$b <- odb_test_authorization(session, "B", "read")
    state$selected <- shiny::reactiveVal(state$a$connection)
    source <- oauth_db_connect(
      state$selected,
      connect = task_sqlite_connect,
      required_scopes = "read"
    )
    rows <- oauth_db_task(source)
    shiny::observeEvent(input$load, rows$invoke("SELECT * FROM identity"))
    output$rows <- shiny::renderTable(rows$result())
  }
  shiny::testServer(server, {
    session$flushReact()
    session$setInputs(load = 1L)
    task_app_flush(session)
    expect_match(output$rows, "fixture-A", fixed = TRUE)
    state$selected(NULL)
    task_app_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
    state$selected(state$a$connection)
    task_app_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(load = 2L)
    task_app_flush(session)
    expect_match(output$rows, "fixture-A", fixed = TRUE)
    state$a$token(state$a$make_token("denied", "other"))
    task_app_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
    state$a$token(state$a$make_token("restored"))
    task_app_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
  })
})

test_that("worker failures retain native classes without retaining credentials", {
  worker <- list(
    type = "native",
    connect = function(token) {
      stop(errorCondition(
        paste("Failure", token()),
        class = "native_worker_failure",
        reason = "fixture",
        status = 403L,
        service_code = paste0("code-", token()),
        request_id = paste0("id-", token())
      ))
    },
    args = list(),
    scopes = list(character())
  )
  value <- .odb_task_job(worker, list("private-bearer"), Inf, "query", list())
  expect_false(value$ok)
  expect_s3_class(value$error, "native_worker_failure")
  expect_identical(value$error$reason, "fixture")
  expect_identical(conditionMessage(value$error), "Failure [REDACTED]")
  expect_null(value$error$call)
  expect_identical(value$error$status, 403L)
  expect_identical(value$error$service_code, "code-[REDACTED]")
  expect_identical(value$error$request_id, "id-[REDACTED]")
  expect_false(grepl(
    "private-bearer",
    rawToChar(serialize(value$error, NULL, ascii = TRUE)),
    fixed = TRUE
  ))
})

test_that("task argument snapshots retain an optional NULL username", {
  value <- .odb_task_arguments(list(
    user = function() NULL,
    url = "mongodb://example"
  ))
  expect_identical(names(value), c("user", "url"))
  expect_null(value$user)
})

test_that("worker functions from sourced apps are detached from the app environment", {
  app <- new.env(parent = globalenv())
  app$private_session_value <- "must-not-be-serialized"
  fun <- eval(
    quote(function(connection, statement) {
      DBI::dbGetQuery(connection, statement)
    }),
    app
  )
  snapshot <- .odb_task_snapshot(list(fetch = fun))
  expect_identical(environment(snapshot$fetch), baseenv())
  encoded <- rawToChar(serialize(snapshot, NULL, ascii = TRUE))
  expect_false(grepl(app$private_session_value, encoded, fixed = TRUE))
  captured <- eval(quote(function(connection) private_session_value), app)
  expect_error(.odb_task_snapshot(captured), "self-contained")
})

test_that("a cancelled settings generation cannot become current again", {
  skip_if_not_installed("mirai", "2.5.1")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    user <- shiny::reactiveVal("A")
    connect <- eval(
      quote(function(token, user) data.frame(user = user)),
      baseenv()
    )
    source <- .odb_bind(auth$connection, connect, user = function() user())
    rows <- oauth_db_task(source, method = identity)
    rows$invoke()
    task_flush()
    expect_length(calls$pending, 1L)
    user("B")
    session$flushReact()
    expect_equal(calls$stopped, 1L)
    user("A")
    session$flushReact()
    calls$pending[[1L]]$resolve(data.frame(user = "A"))
    task_flush()
    expect_error(rows$result(), class = "shiny.silent.error")
  })
})

test_that("embedded callbacks cannot carry app environments into workers", {
  app <- new.env(parent = globalenv())
  app$private_marker <- "must-not-cross-the-worker-boundary"
  callback <- eval(quote(function() 1L), app)
  methods::setClass(
    "OAuthDBTaskSnapshotFixture",
    slots = c(callback = "function")
  )
  withr::defer(methods::removeClass("OAuthDBTaskSnapshotFixture"))
  forbidden <- list(
    structure(1L, callback = callback),
    structure(list(1L), callback = callback),
    as.call(list(as.name("list"), callback)),
    as.expression(list(callback)),
    methods::new("OAuthDBTaskSnapshotFixture", callback = callback)
  )
  for (value in forbidden) {
    expect_error(.odb_task_snapshot(value), "not a function or native handle")
  }
  namespace_callback <- get("identity", baseenv())
  attr(namespace_callback, "private") <- app
  expect_error(.odb_task_snapshot(namespace_callback), "ordinary data")
  snapshot <- .odb_task_snapshot(list(
    callback,
    as.pairlist(list(callback)),
    structure(data.frame(value = 1L), label = "ordinary metadata"),
    quote(list(value = 1L)),
    expression(value + 1L)
  ))
  expect_identical(snapshot[[1L]](), 1L)
  expect_identical(snapshot[[2L]][[1L]](), 1L)
  expect_identical(attr(snapshot[[3L]], "label"), "ordinary metadata")
  expect_identical(snapshot[[4L]], quote(list(value = 1L)))
  expect_identical(snapshot[[5L]], expression(value + 1L))
  expect_false(grepl(
    app$private_marker,
    rawToChar(serialize(snapshot, NULL, ascii = TRUE)),
    fixed = TRUE
  ))
})

test_that("worker usernames retain the native backend's calling convention", {
  for (callback in c(TRUE, FALSE)) {
    worker <- list(
      type = "native",
      connect = if (callback) {
        function(token, user) list(user = user())
      } else {
        function(token, user) list(user = user)
      },
      args = list(user = "alice"),
      user_callback = callback,
      disconnect = function(value) invisible(NULL),
      scopes = list(character())
    )
    expect_identical(
      .odb_task_run(worker, list("fixture"), Inf, identity, list()),
      list(user = "alice")
    )
  }
})
