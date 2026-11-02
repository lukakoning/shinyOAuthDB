test_that("Databricks API supplies current credentials and preserves native calls", {
  skip_if_not_installed("brickster")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "sql")
    selected <- shiny::reactiveVal(NULL)
    api <- oauth_db_databricks_api(selected, "https://Workspace.Example/")
    calls <- new.env(parent = emptyenv())
    calls$n <- 0L
    native <- function(statement, host, token, ...) {
      calls$n <- calls$n + 1L
      list(statement = statement, host = host, token = token, options = list(...))
    }
    expect_s3_class(api, "OAuthDatabricksAPI")
    expect_error(api$call(native, "SELECT 1"), class = "shiny.silent.error")
    expect_identical(calls$n, 0L)
    selected(auth$connection)
    first <- api$call(native, "SELECT 1", catalog = "main")
    expect_identical(first, list(statement = "SELECT 1", host = "workspace.example",
      token = "fixture-A", options = list(catalog = "main")))
    auth$token(auth$make_token("rotated"))
    expect_identical(api$call(native, "SELECT 2")$token, "rotated")
    failure <- structure(list(message = "native error", call = NULL),
      class = c("native_api_error", "error", "condition"))
    failing <- function(host, token) stop(failure)
    observed <- expect_error(api$call(failing), class = "native_api_error")
    expect_identical(class(observed), class(failure))
    expect_identical(conditionMessage(observed), conditionMessage(failure))
    expect_identical(calls$n, 2L)
    selected(NULL)
    expect_error(api$call(native, "SELECT 3"), class = "shiny.silent.error")
    expect_identical(calls$n, 2L)
    expect_output(print(api), "<OAuthDatabricksAPI>")
  })
})

test_that("Databricks API supports Entra targets and checks configured permissions", {
  skip_if_not_installed("brickster")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "read", target = "workspace")
    api <- oauth_db_databricks_api(auth$connection, "workspace.example", auth_mode = "entra",
      target = "workspace", required_scopes = auth$scopes)
    native <- function(host, token) token
    expect_identical(api$call(native), "fixture-A")
    auth$token(auth$make_token("denied", character()))
    expect_error(api$call(native), class = "shiny.silent.error")
  })
})

test_that("Fabric routes one callback across audiences without eager acquisition", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session, unacquired = c("sql", "storage"))
    api <- oauth_db_fabric_api(auth$connection)
    expect_s3_class(api, "OAuthFabricAPI")
    provider <- api$token_provider()
    expect_identical(auth$calls$targets, character())
    expect_identical(provider("https://api.fabric.microsoft.com/.default"), "A-fabric")
    expect_match(provider("https://database.windows.net//.default"), "A-sql")
    expect_match(provider("https://storage.azure.com/.default"), "A-storage")
    expect_identical(auth$calls$targets, c("sql", "storage"))
    expect_identical(provider("https://analysis.windows.net/powerbi/api/Dataset.Read.All"), "A-power_bi")
    expect_identical(provider("https://analysis.windows.net/powerbi/api/GraphQLApi.Execute.All"), "A-power_bi")
    expect_identical(provider("https://api.kusto.windows.net/.default"), "A-kusto")
    expect_error(provider(c("https://storage.azure.com/.default",
      "https://database.windows.net//.default")), class = "shinyOAuthDB_invalid_audience")
    expect_error(provider("https://api.fabric.microsoft.com.evil/.default"),
      class = "shinyOAuthDB_invalid_audience")
    expect_error(provider("https://api.fabric.microsoft.com/nested/.default"),
      class = "shinyOAuthDB_invalid_audience")
    expect_error(provider("https://storage.azure.com/.default?other-resource"),
      class = "shinyOAuthDB_invalid_audience")
    expect_error(provider("https://api.fabric.microsoft.com/Item.ReadWrite.All"),
      class = "shinyOAuth_input_error")
    expect_identical(provider("https://api.fabric.microsoft.com/.default", TRUE), "A-fabric-3")
    expect_identical(auth$calls$targets, c("sql", "storage", "fabric"))
    expect_output(print(api), "<OAuthFabricAPI>")
  })
})

test_that("Fabric providers stay pinned through rotation, replacement and session closure", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  saved <- api <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_fabric_authorization(session)
    b <- odb_test_fabric_authorization(session, id = "B")
    selected <- shiny::reactiveVal(a$connection)
    api <<- oauth_db_fabric_api(selected)
    saved <<- api$token_provider()
    values <- a$tokens()
    values$sql <- a$make_token("sql", "rotated-sql")
    a$tokens(values)
    expect_identical(saved("https://database.windows.net//.default"), "rotated-sql")
    other <- shiny::MockShinySession$new()
    on.exit(other$close(), add = TRUE)
    shiny::withReactiveDomain(other, {
      expect_error(api$token_provider(), class = "shinyOAuthDB_authorization_unavailable")
      expect_error(saved("https://storage.azure.com/.default"),
        class = "shinyOAuthDB_authorization_unavailable")
    })
    selected(b$connection)
    session$flushReact()
    expect_error(saved("https://storage.azure.com/.default"),
      class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(api$token_provider()("https://storage.azure.com/.default"), "B-storage")
    selected(a$connection)
    session$flushReact()
    expect_error(saved("https://storage.azure.com/.default"),
      class = "shinyOAuthDB_authorization_unavailable")
    selected(NULL)
    expect_error(api$call(function(token) stop("Must not call native code")),
      class = "shiny.silent.error")
  })
  expect_error(api$token_provider(), class = "shinyOAuthDB_authorization_unavailable")
  expect_error(saved("https://storage.azure.com/.default"),
    class = "shinyOAuthDB_authorization_unavailable")
})

test_that("Fabric supports custom and untargeted authorizations with lazy missing services", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session, services = c("fabric", "sql"),
      target_names = c(fabric = "discovery", sql = "reporting"))
    api <- oauth_db_fabric_api(auth$connection,
      targets = c(fabric = "discovery", sql = "reporting"))
    provider <- api$token_provider()
    expect_identical(provider("https://database.windows.net//.default"), "A-reporting")
    expect_error(provider("https://storage.azure.com/.default"), class = "shinyOAuthDB_invalid_audience")
    plain <- odb_test_authorization(session, scopes = .odb_fabric_profile("kql")$scopes)
    single <- oauth_db_fabric_api(plain$connection, targets = list(kql = NULL))
    expect_identical(single$token_provider()("https://api.kusto.windows.net/.default"), "fixture-A")
    default <- oauth_db_fabric_api(plain$connection)
    failure <- expect_error(default$token_provider()("https://storage.azure.com/.default"),
      class = "shinyOAuth_access_error")
    expect_identical(failure$context$reason, "unsupported_target")
  })
})

test_that("API clients reject credential overrides and ambiguous audience mappings", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  skip_if_not_installed("brickster")
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session)
    fabric <- oauth_db_fabric_api(auth$connection)
    databricks <- oauth_db_databricks_api(auth$connection, "workspace.example")
    native <- function(...) stop("Native code must not run")
    for (args in list(list(token = "secret"), list(storage_token = "secret"),
                      list(auth_args = list(password = "secret")), list(tenant_id = "other"))) {
      error <- expect_error(do.call(fabric$call, c(list(native), args)), "cannot be overridden")
      expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
    }
    for (args in list(list(token = "secret"), list(host = "other.example"),
                      list(client_secret = "secret"))) {
      expect_error(do.call(databricks$call, c(list(native), args)), "cannot be overridden")
    }
    expect_error(fabric$call("not-a-function"), ".fn must")
    expect_error(fabric$call(function(storage_token, token) stop("Must not run"), "secret"),
      "storage_token.*cannot be overridden")
    expect_error(databricks$call(function(user, host, token) stop("Must not run"), "other-user"),
      "user.*cannot be overridden")
    expect_error(fabric$call(native, timeout = 1, timeout = 2), "unique names")
    expect_error(oauth_db_fabric_api(auth$connection, targets = list()), "targets must")
    expect_error(oauth_db_fabric_api(auth$connection, targets = c(unknown = "x")), "unsupported")
    expect_error(oauth_db_fabric_api(auth$connection, targets = c(dax = "x", graphql = "y")),
      "sharing a resource")
    expect_error(oauth_db_fabric_api(auth$connection, targets = c(fabric = "x", sql = "x")),
      "Different Fabric resources")
    expect_error(oauth_db_fabric_api(auth$connection, targets = list(fabric = NULL, sql = NULL)),
      "NULL supports one resource")
    expect_error(oauth_db_fabric_api(auth$connection, required_scopes = list(unknown = "read")),
      "name services declared")
  })
})

test_that("API reactive consumers follow permissions and grants, not ordinary token rotation", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session, services = "fabric")
    selected <- shiny::reactiveVal(auth$connection)
    api <- oauth_db_fabric_api(selected, targets = c(fabric = "fabric"))
    calls <- new.env(parent = emptyenv())
    calls$n <- 0L
    rows <- shiny::reactive(api$call(function(token) {
      calls$n <- calls$n + 1L
      token("https://api.fabric.microsoft.com/.default")
    }))
    session$flushReact()
    expect_identical(rows(), "A-fabric")
    values <- auth$tokens()
    values$fabric <- auth$make_token("fabric", "rotated")
    auth$tokens(values)
    session$flushReact()
    expect_identical(rows(), "A-fabric")
    expect_identical(calls$n, 1L)
    values$fabric <- auth$make_token("fabric", "denied", scopes = character())
    auth$tokens(values)
    session$flushReact()
    expect_error(rows(), class = "shiny.silent.error")
    selected(NULL)
    session$flushReact()
    expect_error(rows(), class = "shiny.silent.error")
  })
})

test_that("native Fabric discovery retains a provider that can open a SQL connection", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  state <- new.env(parent = emptyenv())
  state$tokens <- character()
  workspace_id <- "11111111-1111-1111-1111-111111111111"
  item_id <- "22222222-2222-2222-2222-222222222222"
  native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(native), add = TRUE)
  local_mocked_bindings(dbConnect = function(drv, ...) {
    state$sql <- list(...)
    native
  }, .package = "DBI")
  httr2::local_mocked_responses(function(req) {
    state$tokens <- c(state$tokens, httr2::req_get_headers(req, redacted = "reveal")$Authorization)
    payload <- if (grepl("/items", req$url, fixed = TRUE)) {
      list(value = list(list(id = item_id, workspaceId = workspace_id,
        type = "Lakehouse", displayName = "Reporting",
        properties = list(sqlEndpointProperties = list(
          connectionString = "example.datawarehouse.fabric.microsoft.com", id = item_id)))))
    } else list(value = list(list(id = workspace_id, displayName = "Reporting")))
    httr2::response(status_code = 200, headers = list(`Content-Type` = "application/json"),
      body = charToRaw(jsonlite::toJSON(payload, auto_unbox = TRUE)))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session, services = c("fabric", "sql"))
    api <- oauth_db_fabric_api(auth$connection)
    workspaces <- api$call(fabricQueryR::fabric_workspaces)
    workspace <- workspaces[[1L]]
    expect_s3_class(workspace, "FabricWorkspace")
    lakehouse <- workspace$items(type = "Lakehouse", detail = FALSE)[[1L]]
    expect_s3_class(lakehouse, "FabricLakehouse")
    con <- lakehouse$sql_connect(database = "Reporting", verbose = FALSE)
    expect_identical(con, native)
    expect_identical(state$tokens, c("Bearer A-fabric", "Bearer A-fabric"))
    expect_identical(state$sql$attributes$azure_token, "A-sql")
    auth$current(FALSE)
    expect_error(workspace$items(), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("native brickster functions keep their result shape through the API client", {
  skip_if_not_installed("brickster")
  httr2::local_mocked_responses(function(req) {
    expect_identical(httr2::req_get_headers(req, redacted = "reveal")$Authorization,
      "Bearer fixture-A")
    httr2::response(status_code = 200, headers = list(`Content-Type` = "application/json"),
      body = charToRaw('{"warehouses":[{"id":"warehouse","name":"Reporting"}]}'))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "all-apis")
    api <- oauth_db_databricks_api(auth$connection, "workspace.example")
    expect_identical(api$call(brickster::db_sql_warehouse_list),
      brickster::db_sql_warehouse_list(host = "workspace.example", token = "fixture-A"))
  })
})

test_that("Fabric optional operation permissions invalidate results and recover errors", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  resource <- "https://api.fabric.microsoft.com"
  scopes <- paste0(resource, "/", c("Workspace.Read.All", "Item.Read.All", "Item.Execute.All"))
  client <- oauth_db_microsoft_client(client_id = "test", redirect_uri = "http://localhost:8100",
    provider = shinyOAuth::oauth_provider_microsoft(tenant = "organizations", userinfo_required = FALSE),
    token_targets = list(fabric = list(resource = resource, scopes = scopes, required_scopes = scopes[[1L]])))
  for (initially_allowed in c(TRUE, FALSE)) odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, target = "fabric", resource = resource,
      scopes = c("Workspace.Read.All", "Item.Read.All", "Item.Execute.All"), client = client)
    if (!initially_allowed) auth$token(auth$make_token("limited", scopes[[1L]]))
    api <- oauth_db_fabric_api(auth$connection, targets = c(fabric = "fabric"))
    item_calls <- workspace_calls <- 0L
    item <- shiny::reactive(api$call(function(token) {
      item_calls <<- item_calls + 1L
      token(scopes[[2L]])
    }))
    workspace <- shiny::reactive(api$call(function(token) {
      workspace_calls <<- workspace_calls + 1L
      token(scopes[[1L]])
    }))
    session$flushReact()
    if (initially_allowed) expect_identical(item(), "fixture-A")
    else expect_error(item(), class = "shinyOAuth_access_error")
    workspace()
    auth$token(auth$make_token("rotated",
      if (initially_allowed) scopes else scopes[[1L]]))
    session$flushReact()
    if (initially_allowed) expect_identical(item(), "fixture-A")
    else expect_error(item(), class = "shinyOAuth_access_error")
    expect_identical(item_calls, 1L)

    if (initially_allowed) {
      auth$token(auth$make_token("limited", scopes[[1L]]))
      session$flushReact()
      expect_error(item(), class = "shinyOAuth_access_error")
      expect_identical(item_calls, 2L)
    }
    auth$token(auth$make_token("restored", scopes))
    session$flushReact()
    expect_identical(item(), "restored")
    expect_identical(item_calls, if (initially_allowed) 3L else 2L)
    auth$token(auth$make_token("unrelated-permission-change", scopes[1:2]))
    session$flushReact()
    expect_identical(item(), "restored")
    workspace()
    expect_identical(workspace_calls, 1L)
    expect_identical(item_calls, if (initially_allowed) 3L else 2L)
  })
})

test_that("Fabric operations subscribe only to targets they actually use", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  odb_test_domain(function(session) {
    a <- odb_test_fabric_authorization(session)
    b <- odb_test_fabric_authorization(session, id = "B")
    selected <- shiny::reactiveVal(a$connection)
    api <- oauth_db_fabric_api(selected)
    fabric_calls <- 0L
    sql_calls <- 0L
    fabric_rows <- shiny::reactive(api$call(function(token) {
      fabric_calls <<- fabric_calls + 1L
      token("https://api.fabric.microsoft.com/.default")
    }))
    sql_rows <- shiny::reactive(api$call(function(token) {
      sql_calls <<- sql_calls + 1L
      token("https://database.windows.net//.default")
    }))
    session$flushReact()
    expect_identical(fabric_rows(), "A-fabric")
    expect_identical(sql_rows(), "A-sql")
    saved <- api$token_provider()
    values <- a$tokens()
    values$sql <- a$make_token("sql", "denied", scopes = character())
    a$tokens(values)
    session$flushReact()
    expect_identical(fabric_rows(), "A-fabric")
    expect_identical(fabric_calls, 1L)
    expect_error(sql_rows(), class = "shiny.silent.error")
    values$sql <- a$make_token("sql", "restored")
    a$tokens(values)
    session$flushReact()
    expect_identical(sql_rows(), "restored")
    expect_identical(fabric_rows(), "A-fabric")
    expect_identical(fabric_calls, 1L)
    values$fabric <- a$make_token("fabric", "rotated")
    a$tokens(values)
    session$flushReact()
    expect_identical(fabric_rows(), "A-fabric")
    expect_identical(fabric_calls, 1L)
    selected(b$connection)
    session$flushReact()
    expect_identical(fabric_rows(), "B-fabric")
    expect_identical(sql_rows(), "B-sql")
    expect_identical(fabric_calls, 2L)
    expect_error(saved("https://api.fabric.microsoft.com/.default"),
      class = "shinyOAuthDB_authorization_unavailable")
  })
})
