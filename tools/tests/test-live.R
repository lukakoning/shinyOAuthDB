root <- normalizePath(file.path("..", ".."), winslash = "/")
pkgload::load_all(root, quiet = TRUE)
source(file.path(root, "tests/integration/source-config.R"), local = TRUE)
source(file.path(root, "tests/integration/bigquery.R"), local = TRUE)
source(file.path(root, "tests/integration/live-transport.R"), local = TRUE)
source(file.path(root, "tests/testthat/helper-authorization.R"), local = TRUE)

testthat::test_that("Databricks live routes use both public helpers with their real SDK", {
  withr::local_envvar(c(OAUTHDB_DATABRICKS_HOST = "workspace.example", OAUTHDB_DATABRICKS_WAREHOUSE = "warehouse"))
  calls <- list()
  testthat::local_mocked_bindings(db_sql_query = function(warehouse_id, statement, token, ...) {
    calls[[length(calls) + 1L]] <<- list(token = token, statement = statement, args = list(...))
    if (grepl("test_connection", statement)) data.frame(test_connection = 1L) else
      data.frame(database_user = token, requested_value = 7L)
  }, .package = "brickster")
  for (route in c("databricks-dbi", "databricks-api", "databricks-dbi-entra", "databricks-api-entra")) {
    odb_test_domain(function(session) {
      entra <- endsWith(route, "-entra")
      auth <- odb_test_authorization(session, scopes = "all-apis", target = if (entra) "databricks" else NULL)
      spec <- live_spec(route)
      accessor <- spec$bind(auth$connection)
      value <- accessor()
      testthat::expect_identical(spec$query(value, spec$native_args(7L))$database_user, "fixture-A")
      testthat::expect_identical(tail(calls, 1L)[[1L]]$args$parameters[[1L]]$value, "7")
      testthat::expect_identical(spec$helper, if (grepl("-api", route)) "oauth_db_databricks_api" else "oauth_db_databricks")
      auth$token(auth$make_token("rotated"))
      testthat::expect_identical(spec$query(accessor(), spec$native_args(7L))$database_user, "rotated")
      auth$current(FALSE)
      testthat::expect_error(spec$query(accessor(), spec$native_args(7L)), class = "shiny.silent.error")
    })
  }
})

testthat::test_that("Fabric live API routes inject the correct public audience callback", {
  withr::local_envvar(c(OAUTHDB_KQL_CLUSTER = "https://cluster.example", OAUTHDB_KQL_DATABASE = "data",
    OAUTHDB_FABRIC_WORKSPACE = "workspace", OAUTHDB_FABRIC_MODEL = "model",
    OAUTHDB_GRAPHQL_API = "https://graphql.example", OAUTHDB_ONELAKE_ITEM = "lakehouse"))
  targets <- c(discovery = "fabric", kql = "kusto", dax = "power_bi", graphql = "power_bi", onelake = "storage")
  audiences <- c(discovery = "https://api.fabric.microsoft.com", kql = "https://api.kusto.windows.net",
    dax = "https://analysis.windows.net/powerbi/api", graphql = "https://analysis.windows.net/powerbi/api",
    onelake = "https://storage.azure.com")
  for (service in names(targets)) local({
    audience <- paste0(audiences[[service]], "/.default")
    operation <- function(..., token) token(audience)
    name <- c(discovery = "fabric_workspaces", kql = "fabric_kql_query", dax = "fabric_pbi_dax_query",
      graphql = "fabric_graphql_query", onelake = "fabric_onelake_list")[[service]]
    do.call(testthat::local_mocked_bindings, c(stats::setNames(list(operation), name),
      list(.package = "fabricQueryR", .env = environment())))
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, target = targets[[service]])
      spec <- live_spec(paste0("fabric-api-", service))
      api <- spec$bind(auth$connection)()
      testthat::expect_s3_class(api, "OAuthFabricAPI")
      testthat::expect_identical(spec$query(api, spec$native_args(7L)), "fixture-A")
      testthat::expect_identical(spec$helper, "oauth_db_fabric_api")
    })
  })
})

testthat::test_that("cloud acceptance rejects false identities, missing denial checks and equal user results", {
  withr::local_envvar(c(OAUTHDB_LIVE_TESTS = "true", OAUTHDB_LIVE_A_TOKEN = "A", OAUTHDB_LIVE_B_TOKEN = "B",
    OAUTHDB_LIVE_A_EXPIRES_AT = as.character(as.numeric(Sys.time()) + 3600),
    OAUTHDB_LIVE_B_EXPIRES_AT = as.character(as.numeric(Sys.time()) + 3600),
    OAUTHDB_LIVE_A_SCOPES = "read", OAUTHDB_LIVE_B_SCOPES = "read"))
  client <- shinyOAuth::oauth_client(shinyOAuth::oauth_provider(name = "fixture",
    auth_url = "https://issuer.example/authorize", token_url = "https://issuer.example/token",
    token_auth_style = "public"), client_id = "fixture", redirect_uri = "http://localhost:8100", scopes = "read")
  spec <- list(route = "fixture", helper = "oauth_db_connect", auth_mode = "synthetic", retires_handle = TRUE,
    bind = function(auth) shinyOAuthDB::oauth_db_connect(auth, connect = function(token) {
      con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(con, "identity", data.frame(marker = token))
      con
    }), native_args = function(value) list(statement = "SELECT marker FROM identity"),
    query = function(native, args) do.call(DBI::dbGetQuery, c(list(conn = native), args)))
  runner <- run_live_transport
  environment(runner) <- list2env(list(live_spec = function(...) spec, live_client = function(...) client),
    parent = environment(run_live_transport))
  fixture <- list(backend = "fixture", users = c(A = "A", B = "B"),
    validate = function(user, value) identical(value$marker, user),
    identify = function(user, native, spec) spec$query(native, spec$native_args(7L))$marker[[1L]],
    denied = function(user, native, spec) TRUE)
  result <- runner(fixture)
  testthat::expect_identical(result$status, "pass")
  testthat::expect_true(all(c("A_identity", "B_identity", "A_handle_retired", "logout_blocks_query",
    "closed_session_blocks_query", "B_handle_closed") %in% result$scenarios))
  bad <- fixture
  bad$identify <- function(...) "wrong"
  testthat::expect_error(runner(bad), "A_identity")
  bad <- fixture
  bad$denied <- NULL
  testthat::expect_error(runner(bad), "denied")
  bad <- fixture
  bad$denied <- function(...) FALSE
  testthat::expect_error(runner(bad), "A_denied")
  bad <- fixture
  bad$validate <- function(...) TRUE
  equal_spec <- spec
  equal_spec$query <- function(...) data.frame(marker = "same")
  bad$identify <- function(user, native, spec) DBI::dbReadTable(native, "identity")$marker[[1L]]
  equal_runner <- runner
  environment(equal_runner) <- list2env(list(live_spec = function(...) equal_spec, live_client = function(...) client),
    parent = environment(run_live_transport))
  testthat::expect_error(equal_runner(bad), "distinct_results")
})

testthat::test_that("a retained Fabric resource keeps its original multi-audience authorization", {
  withr::local_envvar(c(OAUTHDB_FABRIC_WORKSPACE = "workspace", OAUTHDB_ONELAKE_ITEM = "lakehouse",
    OAUTHDB_ONELAKE_TABLE = "rows", OAUTHDB_LIVE_A_TOKENS_JSON = NA, OAUTHDB_LIVE_B_TOKENS_JSON = NA))
  client <- shinyOAuthDB::oauth_db_microsoft_client(c("fabric", "onelake"), "organizations", "fixture", "http://localhost:8100")
  encode <- function(user) jsonlite::toJSON(lapply(names(client@token_targets), function(target) {
    list(access_token = paste(user, target, sep = "-"), expires_at = as.numeric(Sys.time()) + 3600,
      scopes = unname(as.list(client@token_targets[[target]]$scopes)))
  }) |> stats::setNames(names(client@token_targets)), auto_unbox = TRUE)
  withr::local_envvar(c(OAUTHDB_LIVE_A_TOKENS_JSON = encode("A"), OAUTHDB_LIVE_B_TOKENS_JSON = encode("B")))
  testthat::local_mocked_bindings(fabric_item = function(..., token) {
    token("https://api.fabric.microsoft.com/.default")
    list(read_table = function(...) token("https://storage.azure.com/.default"))
  }, .package = "fabricQueryR")
  odb_test_domain(function(session) {
    current <- shiny::reactiveVal(NULL)
    a <- live_fixture_authorization(client, "A", current, session)
    b <- live_fixture_authorization(client, "B", current, session)
    spec <- live_spec("fabric-api-resource")
    current(a)
    accessor <- spec$bind(current)
    held <- accessor()
    testthat::expect_identical(spec$query(held, spec$native_args(7L)), "A-storage")
    current(b)
    session$flushReact()
    testthat::expect_error(spec$query(held, spec$native_args(7L)), class = "shinyOAuthDB_authorization_unavailable")
    testthat::expect_identical(spec$query(accessor(), spec$native_args(7L)), "B-storage")
    withr::local_envvar(c(OAUTHDB_LIVE_A_TOKENS_JSON = "{}"))
    testthat::expect_error(live_fixture_authorization(client, "A", current, session), "named target")
  })
})

testthat::test_that("BigQuery acceptance uses the public capped regional paginator", {
  withr::local_envvar(c(OAUTHDB_BIGQUERY_PROJECT = "fixture-project", OAUTHDB_BIGQUERY_DATASET = "reporting",
    OAUTHDB_BIGQUERY_TABLE = "visible_rows", OAUTHDB_BIGQUERY_LOCATION = "EU"))
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    result <- list(jobComplete = TRUE, jobReference = list(projectId = "fixture-project", jobId = "job", location = "EU"),
      schema = list(fields = list(list(name = "database_user", type = "STRING"), list(name = "visible_marker", type = "STRING"))),
      rows = list(list(f = list(list(v = "a@example.org"), list(v = if (req$method == "POST") "A-first" else "A-second")))))
    if (req$method == "POST") result$pageToken <- "second"
    httr2::response(status_code = 200L, headers = list(`content-type` = "application/json"),
      body = charToRaw(jsonlite::toJSON(result, auto_unbox = TRUE)))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    spec <- live_spec("bigquery")
    api <- spec$bind(auth$connection)()
    testthat::expect_s3_class(api, "OAuthBigQueryAPI")
    rows <- spec$query(api, spec$native_args(7L))
    testthat::expect_identical(rows$visible_marker, c("A-first", "A-second"))
    testthat::expect_identical(spec$auth_mode, "google")
    testthat::expect_length(requests, 2L)
    body <- requests[[1L]]$body$data
    testthat::expect_identical(body$maximumBytesBilled, "10485760")
    testthat::expect_identical(body$maxResults, 1L)
    testthat::expect_identical(body$location, "EU")
    testthat::expect_false(body$useQueryCache)
  })
  testthat::expect_error(live_bigquery_table("rows`; SELECT 1"), "identifiers")
})
