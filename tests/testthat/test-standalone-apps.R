# Source-checkout tests execute the real playground server definitions. Only
# external OAuth/native transport boundaries and worker submission are mocked.
standalone_app_cases <- list(
  list(file = "example-azure-sql.R", backend = "azure_sql", package = "DBI", fun = "dbGetQuery", numeric = TRUE),
  list(file = "example-sql-server.R", backend = "sql_server", package = "DBI", fun = "dbGetQuery", numeric = TRUE),
  list(file = "example-azure-postgres.R", backend = "azure_postgres", package = "DBI", fun = "dbGetQuery", numeric = TRUE),
  list(file = "example-fabric-sql.R", backend = "fabric_sql", package = "DBI", fun = "dbGetQuery", numeric = TRUE),
  list(file = "example-snowflake.R", backend = "snowflake", package = "DBI", fun = "dbGetQuery", numeric = TRUE),
  list(file = "example-fabric-kql.R", backend = "fabric", package = "fabricQueryR", fun = "fabric_kql_query", numeric = TRUE),
  list(file = "example-fabric-dax.R", backend = "fabric", package = "fabricQueryR", fun = "fabric_pbi_dax_query", numeric = FALSE),
  list(file = "example-fabric-graphql.R", backend = "fabric", package = "fabricQueryR", fun = "fabric_graphql_query", numeric = FALSE),
  list(file = "example-fabric-onelake.R", backend = "fabric", package = "fabricQueryR", fun = "fabric_onelake_list", numeric = FALSE),
  list(file = "example-fabric-discovery.R", backend = "fabric", package = "fabricQueryR", fun = "fabric_workspaces", numeric = FALSE),
  list(file = "example-databricks.R", backend = "databricks", package = "brickster", fun = "db_sql_query", numeric = TRUE)
)

standalone_app_env <- function() c(
  OAUTHDB_TENANT_ID = "11111111-1111-4111-8111-111111111111",
  OAUTHDB_CLIENT_ID = "22222222-2222-4222-8222-222222222222",
  OAUTHDB_CLIENT_SECRET = "", OAUTHDB_REDIRECT_URI = "http://localhost:8100",
  OAUTHDB_PORT = "8100", OAUTHDB_EXECUTOR = "mirai",
  OAUTHDB_SERVER = "fixture.database.windows.net", OAUTHDB_DATABASE = "fixture",
  OAUTHDB_SQL_SERVER_ENTRA_ENABLED = "true",
  OAUTHDB_POSTGRES_HOST = "fixture.postgres.database.azure.com",
  OAUTHDB_POSTGRES_USER = "fixture-role", OAUTHDB_POSTGRES_SSLROOTCERT = "fixture-ca.pem",
  OAUTHDB_SNOWFLAKE_SERVER = "fixture.snowflakecomputing.com",
  OAUTHDB_SNOWFLAKE_SCHEMA = "PUBLIC", OAUTHDB_SNOWFLAKE_WAREHOUSE = "FIXTURE_WH",
  OAUTHDB_SNOWFLAKE_ROLE = "READER", OAUTHDB_SNOWFLAKE_RESOURCE = "api://fixture",
  OAUTHDB_SNOWFLAKE_SCOPES = "api://fixture/session:role:READER",
  OAUTHDB_DATABRICKS_HOST = "https://fixture.azuredatabricks.net",
  OAUTHDB_DATABRICKS_WAREHOUSE = "fixture-warehouse",
  OAUTHDB_KQL_CLUSTER = "https://fixture.kusto.fabric.microsoft.com",
  OAUTHDB_KQL_DATABASE = "fixture-kql",
  OAUTHDB_FABRIC_WORKSPACE = "33333333-3333-4333-8333-333333333333",
  OAUTHDB_FABRIC_MODEL = "44444444-4444-4444-8444-444444444444",
  OAUTHDB_GRAPHQL_API = "55555555-5555-4555-8555-555555555555",
  OAUTHDB_GRAPHQL_QUERY = "query Playground { __typename }",
  OAUTHDB_GRAPHQL_ENDPOINT_HOSTS = "api.fabric.microsoft.com",
  OAUTHDB_ONELAKE_ITEM = "Fixture.Lakehouse", OAUTHDB_ONELAKE_PATH = "Files"
)

standalone_app_provider <- function(host, token_auth_style = "public") {
  shinyOAuth::oauth_provider(
    name = "databricks", auth_url = paste0(host, "/oidc/v1/authorize"),
    token_url = paste0(host, "/oidc/v1/token"),
    token_auth_style = token_auth_style, use_pkce = TRUE
  )
}

standalone_app_request <- function() list(
  REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = "",
  HTTP_HOST = "localhost:8100", SERVER_NAME = "localhost", SERVER_PORT = "8100",
  rook.url_scheme = "http"
)

# Keep native formals and defaults so descriptor binding is tested against the
# existing exported API, rather than a permissive substitute with only dots.
standalone_app_spy <- function(original, handler) {
  spy <- original
  body(spy) <- quote({
    argument_names <- setdiff(names(formals(sys.function())), "...")
    args <- mget(argument_names, envir = environment(), inherits = FALSE)
    if ("..." %in% names(formals(sys.function()))) args <- c(args, list(...))
    .standalone_spy_handler(args)
  })
  environment(spy) <- list2env(list(.standalone_spy_handler = handler),
                               parent = environment(original))
  spy
}

standalone_app_module <- function(app, calls) {
  function(id, client, ...) {
    session <- shiny::getDefaultReactiveDomain()
    selected <- shiny::reactiveVal(NULL)
    allowed_scopes <- shiny::reactiveVal(app$db_source$auth$scopes)
    calls$current_id <- "A"
    make_reference <- function(user) {
      token <- shiny::reactive(shinyOAuth::OAuthToken(
        access_token = paste0("fixture-", user), token_type = "Bearer",
        expires_at = as.numeric(Sys.time()) + 3600,
        granted_scopes = allowed_scopes(), granted_scopes_verified = TRUE
      ))
      getFromNamespace("OAuthConnection", "shinyOAuth")$new(
        id = user, client = client,
        resolve = function() {
          current <- selected()
          domain <- shiny::getDefaultReactiveDomain()
          if (is.null(current) || !identical(current$id, user) ||
              is.null(domain) || isTRUE(session$isClosed()) ||
              !identical(domain$rootScope(), session$rootScope())) stop("Fixture grant ended")
          list(client = client, token = token(), status = "active", targets = NULL)
        },
        acquire = function(...) stop("Synthetic grants must not start OAuth acquisition"),
        is_current = function() {
          # Constructors snapshot this predicate before selected(new_ref) can
          # publish the reference. Declare the next ID first, while retaining
          # a reactive dependency for later replacement/logout notifications.
          selected()
          identical(calls$current_id, user)
        }
      )
    }
    selected(make_reference("A"))
    calls$select <- function(user) {
      calls$current_id <- user
      selected(make_reference(user))
    }
    calls$set_scopes <- function(scopes) allowed_scopes(scopes)
    list(
      connection = function() selected(),
      request_login = function() calls$login <- calls$login + 1L,
      logout = function() {
        calls$logout <- calls$logout + 1L
        calls$current_id <- NULL
        selected(NULL)
      }
    )
  }
}

standalone_app_task <- function(calls) {
  function(db, fun, executor, effect, pending, ...) {
    spec <- .odb_operation_spec(db$.source(), fun)
    calls$task_spec <- spec
    calls$task_setup <- list(executor = executor, effect = effect, pending = pending)
    list(
      invoke = function(...) {
        args <- list(...)
        .odb_task_check_args(args, spec)
        calls$invocations <- c(calls$invocations, list(args))
        invisible(TRUE)
      },
      status = function() "initial",
      result = function() shiny::req(FALSE),
      cancel = function() calls$cancel <- calls$cancel + 1L
    )
  }
}

test_that("standalone live apps build their real source, client and Shiny UI", {
  withr::local_envvar(standalone_app_env())
  if (requireNamespace("brickster", quietly = TRUE)) {
    local_mocked_bindings(db_oauth_provider = standalone_app_provider, .package = "brickster")
  }
  for (case in standalone_app_cases) {
    if (!requireNamespace(case$package, quietly = TRUE)) next
    app <- playground_load_example(case$file)
    expect_s3_class(app$db_source, "oauth_db_source")
    expect_identical(app$db_source$backend, case$backend, info = case$file)
    expect_s3_class(app$app, "shiny.appobj")
    expect_true(is.function(app$server), info = case$file)
    expect_identical(app$client@client_id, standalone_app_env()[["OAUTHDB_CLIENT_ID"]])
    expect_identical(app$client@redirect_uri, "http://localhost:8100")
    expect_true(all(app$db_source$auth$scopes %in% app$client@scopes), info = case$file)
    expect_true(app$client@provider@use_pkce, info = case$file)
    if (case$backend == "databricks") {
      expect_setequal(app$client@scopes, c("openid", "profile", "offline_access", "sql"))
    } else {
      expect_identical(app$client@default_token_target, app$db_source$auth$target)
      expect_identical(app$client@token_targets[[app$db_source$auth$target]]$resource,
                       app$db_source$auth$resource)
    }
    response <- app$ui(standalone_app_request())
    expect_equal(response$status, 200L, info = case$file)
    expect_match(response$content, 'id="login"', fixed = TRUE, info = case$file)
    expect_match(response$content, 'id="run_sync"', fixed = TRUE, info = case$file)
    expect_match(response$content, 'id="run_async"', fixed = TRUE, info = case$file)
    if (!case$numeric) expect_false(grepl('id="value"', response$content, fixed = TRUE))
    spec <- .odb_operation_spec(app$db_source, getExportedValue(case$package, case$fun))
    expect_identical(spec$package, case$package)
    expect_identical(spec$fun, case$fun)
    if (case$fun == "fabric_graphql_query") {
      expect_identical(app$db_source$config$endpoint_hosts, "api.fabric.microsoft.com")
      expect_identical(spec$bindings$api, standalone_app_env()[["OAUTHDB_GRAPHQL_API"]])
    }
  }
})

test_that("standalone apps reject missing registration and untrusted GraphQL hosts", {
  withr::local_envvar(standalone_app_env())
  withr::local_envvar(c(OAUTHDB_CLIENT_ID = ""))
  expect_error(playground_load_example("example-azure-sql.R"), "OAUTHDB_CLIENT_ID")
  expect_error(playground_load_example("example-fabric-kql.R"), "required")
  withr::local_envvar(c(OAUTHDB_CLIENT_ID = standalone_app_env()[["OAUTHDB_CLIENT_ID"]],
                      OAUTHDB_GRAPHQL_ENDPOINT_HOSTS = "*.untrusted.example"))
  expect_error(playground_load_example("example-fabric-graphql.R"), "exact trusted hostnames")
})

for (standalone_case in standalone_app_cases) {
  local({
    case <- standalone_case
    test_that(paste(case$file, "uses native arguments and guards A/B results"), {
      skip_if_not_installed(case$package)
      skip_if_not_installed("RSQLite")
      withr::local_envvar(standalone_app_env())
      if (case$package == "brickster") {
        local_mocked_bindings(db_oauth_provider = standalone_app_provider, .package = "brickster")
      }
      app <- playground_load_example(case$file)
      calls <- new.env(parent = emptyenv())
      calls$requests <- list()
      calls$connections <- list()
      calls$invocations <- list()
      calls$login <- 0L
      calls$logout <- 0L
      calls$cancel <- 0L
      calls$fail <- FALSE
      original <- getExportedValue(case$package, case$fun)
      spy <- standalone_app_spy(original, function(args) {
        calls$requests <- c(calls$requests, list(args))
        if (calls$fail) stop("fixture-private-request-details")
        user <- if (case$package == "DBI") attr(args$conn, "standalone_user") else {
          sub("^fixture-", "", args$token())
        }
        data.frame(user = user, stringsAsFactors = FALSE)
      })
      do.call(local_mocked_bindings, c(stats::setNames(list(spy), case$fun),
                                      list(.package = case$package, .env = environment())))
      local_mocked_bindings(oauth_module_server = standalone_app_module(app, calls),
                            .package = "shinyOAuth")
      local_mocked_bindings(
        .odb_adapter_token_provider = function(source, credential_fun) credential_fun,
        .odb_adapter_connect = function(source, token_provider) {
          user <- sub("^fixture-", "", token_provider())
          native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          attr(native, "standalone_user") <- user
          calls$connections <- c(calls$connections, list(native))
          native
        },
        oauth_db_task = standalone_app_task(calls),
        .package = "shinyOAuthDB"
      )

      shiny::testServer(app$server, {
        session$setInputs(value = 7L, include_nulls = TRUE, recursive = TRUE, role = "Viewer")
        expect_identical(authorization()$id, "A")
        expect_identical(db$status()$status, "ready")
        session$setInputs(login = 1L)
        expect_equal(calls$login, 1L)
        session$setInputs(run_sync = 1L)
        expect_identical(sync_result()$user, "A")
        expect_length(calls$requests, 1L)
        first_connection <- if (case$package == "DBI") db$connection() else NULL
        session$setInputs(run_sync = 2L)
        expect_identical(sync_result()$user, "A")
        if (case$package == "DBI") {
          expect_identical(db$connection(), first_connection)
          expect_length(calls$connections, 1L)
          expect_identical(calls$requests[[1L]]$params, list(7L))
          expect_identical(calls$requests[[1L]]$statement, app$query_sql)
        }
        session$setInputs(run_async = 1L)
        expect_length(calls$invocations, 1L)
        expect_identical(calls$task_spec$package, case$package)
        expect_identical(calls$task_spec$fun, case$fun)
        expect_identical(calls$task_setup,
                         list(executor = "mirai", effect = "read", pending = "latest"))
        task_args <- calls$invocations[[1L]]
        expect_silent(.odb_task_check_args(task_args, calls$task_spec))
        expect_false(any(names(task_args) %in% calls$task_spec$protected_args))
        expect_identical(calls$requests[[1L]][names(task_args)], task_args)
        if (case$fun == "dbGetQuery") {
          expect_identical(task_args, list(statement = app$query_sql, params = list(7L)))
        } else if (case$fun == "fabric_kql_query") {
          expect_identical(task_args, list(query = app$query, parameters = list(value = 7L)))
          expect_identical(calls$requests[[1L]]$cluster, app$config$cluster)
          expect_identical(calls$requests[[1L]]$database, app$config$database)
        } else if (case$fun == "fabric_pbi_dax_query") {
          expect_identical(task_args, list(dax = app$dax, result = "tibble", include_nulls = TRUE))
          expect_identical(calls$requests[[1L]]$workspace_id, app$config$workspace_id)
          expect_identical(calls$requests[[1L]]$dataset_id, app$config$dataset_id)
        } else if (case$fun == "fabric_graphql_query") {
          expect_identical(task_args, list(query = app$query, error_policy = "error"))
          expect_identical(calls$requests[[1L]]$api, app$config$api)
          expect_identical(calls$requests[[1L]]$workspace_id, app$workspace_id)
        } else if (case$fun == "fabric_onelake_list") {
          expect_identical(task_args, list(path = "Files", recursive = TRUE))
          expect_identical(calls$requests[[1L]]$workspace, app$config$workspace)
          expect_identical(calls$requests[[1L]]$item, app$config$item)
        } else if (case$fun == "fabric_workspaces") {
          expect_identical(task_args, list(roles = "Viewer"))
          expect_identical(calls$requests[[1L]]$output, "list")
        } else {
          expect_identical(task_args$statement, app$statement)
          expect_identical(task_args$parameters,
                           list(list(name = "value", value = "7", type = "INT")))
          expect_identical(task_args$disposition, "INLINE")
          expect_false(task_args$show_progress)
          expect_identical(calls$requests[[1L]]$host, app$config$host)
          expect_identical(calls$requests[[1L]]$warehouse_id, app$config$warehouse_id)
        }
        if (case$numeric) {
          request_count <- length(calls$requests)
          invocation_count <- length(calls$invocations)
          session$setInputs(value = 1.25, run_sync = 3L, run_async = 2L)
          expect_length(calls$requests, request_count)
          expect_length(calls$invocations, invocation_count)
          session$setInputs(value = 9L, run_sync = 4L)
          expect_identical(sync_result()$user, "A")
          query_field <- if (case$fun == "fabric_kql_query") "query" else "statement"
          expect_identical(calls$requests[[1L]][[query_field]],
                           calls$requests[[length(calls$requests)]][[query_field]])
        }

        old_provider <- db$token_provider()
        calls$select("B")
        session$flushReact()
        expect_null(last_result())
        expect_null(last_error())
        expect_error(sync_result(), class = "shiny.silent.error")
        expect_error(old_provider(), class = "shinyOAuthDB_authorization_unavailable")
        if (!is.null(first_connection)) expect_false(DBI::dbIsValid(first_connection))
        session$setInputs(run_sync = 5L)
        expect_identical(sync_result()$user, "B")
        expect_gte(calls$cancel, 2L)

        calls$fail <- TRUE
        session$setInputs(run_sync = 6L)
        expect_null(last_result())
        expect_false(grepl("fixture-private-request-details", last_error()$message, fixed = TRUE))
        calls$fail <- FALSE
        session$setInputs(run_sync = 7L)
        expect_identical(sync_result()$user, "B")
        # A .default-only consent profile has no declared permission evidence
        # to lose. Explicit required scopes can invalidate this same grant.
        if (length(app$db_source$auth$required_scopes)) {
          calls$set_scopes(character())
          session$flushReact()
          expect_null(last_result())
          expect_null(last_error())
          expect_error(sync_result(), class = "shiny.silent.error")
          expect_identical(db$status()$status, "needs_authorization")
          calls$set_scopes(app$db_source$auth$scopes)
          session$flushReact()
          session$setInputs(run_sync = 8L)
          expect_identical(sync_result()$user, "B")
        }

        session$setInputs(logout = 1L)
        expect_equal(calls$logout, 1L)
        expect_null(last_result())
        expect_null(last_error())
        expect_error(sync_result(), class = "shiny.silent.error")
        expect_identical(db$status()$status, "waiting_for_authorization")
        request_count <- length(calls$requests)
        session$setInputs(run_sync = 9L)
        expect_length(calls$requests, request_count)
      })
      for (native in calls$connections) expect_false(DBI::dbIsValid(native))
    })
  })
}
