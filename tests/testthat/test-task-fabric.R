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

test_that("multi-service tasks budget each token from its own delivery time", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("fabricQueryR", "1.0.1")
  now <- 1000
  local_mocked_bindings(.odb_task_time = function() now)
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    resolve <- list()
    grant <- list(
      id = "pending-services",
      has_scopes = function(...) TRUE,
      summary = function() list(status = "active"),
      targets = function() {
        list(
          fabric = list(status = "active"),
          sql = list(status = "active")
        )
      },
      access_token = function(target, ...) {
        promises::promise(function(yes, no) {
          resolve[[target]] <<- yes
        })
      }
    )
    api <- oauth_db_fabric_api(
      grant,
      targets = c(fabric = "fabric", sql = "sql"),
      min_valid_for = 0
    )
    rows <- oauth_db_task(api, min_valid_for = 20)
    rows$invoke()
    task_app_flush(session)
    now <<- 1005
    resolve$fabric("first-token")
    task_app_flush(session)
    expect_length(calls$pending, 0L)
    now <<- 1010
    resolve$sql("second-token")
    task_app_flush(session)
    expect_length(calls$pending, 1L)
    expect_identical(calls$pending[[1L]]$arguments$until, c(1025, 1030))
  })
})

test_that("Fabric GraphQL tasks validate default permissions and call the native SDK", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  task_app_workers()
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    expect_identical(
      httr2::req_get_headers(req, redacted = "reveal")$Authorization,
      "Bearer A-power_bi"
    )
    odb_http_response('{"data":{"value":42}}')
  })
  server <- function(input, output, session) {
    auth <- odb_test_fabric_authorization(session, services = "graphql")
    api <- oauth_db_fabric_api(
      auth$connection,
      targets = c(graphql = "power_bi")
    )
    rows <- oauth_db_task(api, method = "call")
  }
  shiny::testServer(server, {
    expect_true(rows$invoke(
      fabricQueryR::fabric_graphql_query,
      api = paste0(
        "https://api.fabric.microsoft.com/v1/workspaces/",
        "11111111-1111-1111-1111-111111111111/graphqlapis/",
        "22222222-2222-2222-2222-222222222222/graphql"
      ),
      query = "{ value }"
    ))
    task_app_flush(session)
    expect_identical(rows$status(), "success")
    expect_equal(rows$result()$data$value, 42)
  })
  expect_identical(requests, 1L)
})

test_that("Fabric task defaults merge shared resources and permit explicit scope choices", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session)
    api <- oauth_db_fabric_api(
      auth$connection,
      targets = c(dax = "power_bi", graphql = "power_bi")
    )
    spec <- .odb_task_source(api)
    expect_length(spec$plans, 1L)
    expect_setequal(
      spec$worker$scopes[[1L]],
      paste0(
        "https://analysis.windows.net/powerbi/api/",
        c("Dataset.Read.All", "GraphQLApi.Execute.All")
      )
    )
    custom <- oauth_db_fabric_api(
      auth$connection,
      targets = c(fabric = "fabric"),
      required_scopes = list(
        fabric = "https://api.fabric.microsoft.com/Workspace.Read.All"
      )
    )
    expect_identical(
      .odb_task_source(custom)$worker$scopes,
      list("https://api.fabric.microsoft.com/Workspace.Read.All")
    )
    expect_error(
      .odb_task_run(
        .odb_task_source(custom)$worker,
        list("fixture"),
        Inf,
        "call",
        list(function(token) {
          token("https://api.fabric.microsoft.com/Item.ReadWrite.All")
        })
      ),
      class = "shinyOAuthDB_insufficient_scope"
    )
  })
})

test_that("Fabric tasks reject denied default scopes and retire results after scope loss", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  scope <- "https://analysis.windows.net/powerbi/api/GraphQLApi.Execute.All"
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    held <- shiny::reactiveVal(character())
    grant <- list(
      id = "task-permissions",
      has_scopes = function(required_scopes, ...) {
        all(required_scopes %in% held())
      },
      targets = function() list(power_bi = list(status = "active")),
      access_token = function(required_scopes, async = FALSE, ...) {
        expect_setequal(required_scopes, scope)
        expect_true(all(required_scopes %in% held()))
        if (async) promises::promise_resolve("fixture") else "fixture"
      }
    )
    api <- oauth_db_fabric_api(grant, targets = c(graphql = "power_bi"))
    rows <- oauth_db_task(api, method = "call")
    expect_error(
      rows$invoke(identity),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    expect_length(calls$pending, 0L)
    held(scope)
    rows$invoke(identity)
    task_app_flush(session)
    expect_length(calls$pending, 1L)
    calls$pending[[1L]]$resolve(data.frame(value = 1L))
    task_app_flush(session)
    expect_identical(rows$result(), data.frame(value = 1L))
    held(character())
    task_app_flush(session)
    expect_identical(rows$status(), "initial")
    expect_error(rows$result(), class = "shiny.silent.error")
    held(scope)
    task_app_flush(session)
    expect_identical(rows$status(), "initial")
    expect_length(calls$pending, 1L)
    rows$invoke(identity)
    task_app_flush(session)
    expect_length(calls$pending, 2L)
    held(character())
    task_app_flush(session)
    expect_identical(calls$stopped, 1L)
    calls$pending[[2L]]$resolve(data.frame(value = 2L))
    held(scope)
    task_app_flush(session)
    expect_identical(rows$status(), "initial")
    expect_error(rows$result(), class = "shiny.silent.error")
  })
})
