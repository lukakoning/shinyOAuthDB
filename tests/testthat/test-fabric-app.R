test_that("the integrated Fabric app builds a normal multi-target OAuth client", {
  withr::local_envvar(c(playground_env(), FABRIC_SHINY_AUTH = "delegated"))
  app <- playground_fabric_app()
  expect_s3_class(app$app, "shiny.appobj")
  expect_setequal(names(app$client@token_targets), c("fabric", "sql", "power_bi", "kusto", "storage"))
  expect_identical(app$workspace_name, "fabricqueryr-shiny-dhrkoning")
  response <- app$ui(playground_request())
  expect_equal(response$status, 200L)
  expect_match(response$content, "Warehouse / SQL", fixed = TRUE)
  expect_match(response$content, "GraphQL / paginated", fixed = TRUE)
})

test_that("the integrated app routes all native reads and clears results on logout", {
  skip_if_not_installed("fabricQueryR")
  withr::local_envvar(c(playground_env(), FABRIC_SHINY_AUTH = "delegated"))
  app <- playground_fabric_app()
  calls <- new.env(parent = emptyenv())
  calls$requests <- list()
  calls$login <- 0L
  calls$fail <- FALSE
  app$oauth_module_server <- playground_module(calls)
  fixture_items <- Map(function(name, type) list(displayName = name, type = type),
    c("TestWarehouse", "TestLakehouse", "FabricQueryRIntegrationModel", "FabricQueryRArrowIntegrationModel",
      "TestKQLDatabase", "TestMirroredDatabase", "TestGraphQL"),
    c("Warehouse", "Lakehouse", "SemanticModel", "SemanticModel", "KQLDatabase", "MirroredDatabase", "GraphQLApi"))
  audiences <- c(fabric = "https://api.fabric.microsoft.com/.default",
    sql = "https://database.windows.net//.default", dax = "https://analysis.windows.net/powerbi/api/.default",
    kql = "https://api.kusto.windows.net/.default", onelake = "https://storage.azure.com/.default",
    graphql = "https://analysis.windows.net/powerbi/api/GraphQLApi.Execute.All")
  read <- function(fun, service) playground_spy(getExportedValue("fabricQueryR", fun), function(args) {
    value <- args$token(audiences[[service]])
    calls$requests <- c(calls$requests, list(list(fun = fun, token = value, args = args)))
    if (calls$fail) stop("Native service failed")
    data.frame(Category = value, Rows = 1L, Amount = 10.5)
  })
  local_mocked_bindings(
    fabric_workspaces = function(..., token) {
      token(audiences[["fabric"]])
      list(list(displayName = "fabricqueryr-shiny-dhrkoning"))
    },
    fabric_items = function(..., token) {
      token(audiences[["fabric"]])
      fixture_items
    },
    fabric_sql_query = read("fabric_sql_query", "sql"),
    fabric_pbi_dax_query = read("fabric_pbi_dax_query", "dax"),
    fabric_kql_query = read("fabric_kql_query", "kql"),
    fabric_onelake_read_file = read("fabric_onelake_read_file", "onelake"),
    fabric_lakehouse_read_table = read("fabric_lakehouse_read_table", "onelake"),
    fabric_mirrored_database_read_table = read("fabric_mirrored_database_read_table", "onelake"),
    fabric_graphql_paginate = read("fabric_graphql_paginate", "graphql"),
    fabric_graphql_collect = function(pages, ...) pages,
    .package = "fabricQueryR")
  shiny::testServer(app$server, {
    session$setInputs(source = "warehouse", backend = "odbc", min_id = 1L, category = "All", run = 0L)
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(run = 1L)
    expect_match(output$rows, "fixture-A", fixed = TRUE)
    expect_identical(tail(calls$requests, 1L)[[1L]]$args$params, list(1L))
    for (source in setdiff(unname(app$fabric_demo_sources), "discovery")) {
      session$setInputs(source = source)
      expect_match(output$rows, "fixture-A", fixed = TRUE)
    }
    expect_setequal(vapply(calls$requests, `[[`, character(1), "fun"),
      c("fabric_sql_query", "fabric_pbi_dax_query", "fabric_kql_query", "fabric_onelake_read_file",
        "fabric_lakehouse_read_table", "fabric_mirrored_database_read_table", "fabric_graphql_paginate"))
    calls$select("B")
    session$flushReact()
    expect_match(output$rows, "fixture-B", fixed = TRUE)
    expect_false(grepl("fixture-A", output$rows))
    calls$fail <- TRUE
    session$setInputs(source = "kql")
    expect_error(output$rows, "Native service failed")
    calls$fail <- FALSE
    session$setInputs(source = "files")
    expect_match(output$rows, "fixture-B", fixed = TRUE)
    session$setInputs(logout = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
    expect_error(output$items, class = "shiny.silent.error")
  })
})

test_that("the integrated app keeps delegated and shared credentials separate", {
  withr::local_envvar(c(playground_env(), FABRIC_SHINY_AUTH = "delegated",
    FABRICQUERYR_TENANT_ID = "sandbox", FABRICQUERYR_CLIENT_ID = "sandbox", FABRICQUERYR_CLIENT_SECRET = "sandbox"))
  delegated <- playground_fabric_app()
  expect_null(delegated$shared_token)
  expect_identical(delegated$mode, "delegated")
  withr::local_envvar(FABRIC_SHINY_AUTH = "sandbox")
  shared <- playground_fabric_app()
  expect_null(shared$client)
  expect_true(is.function(shared$shared_token))
  expect_match(as.character(shared$ui), "Shared sandbox identity", fixed = TRUE)
})
