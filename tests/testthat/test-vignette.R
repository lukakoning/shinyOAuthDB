vignette_chunks <- function(name) {
  path <- test_path("..", "..", "vignettes", paste0(name, ".Rmd"))
  skip_if_not(file.exists(path), "Vignette source is unavailable")
  chunks <- list()
  label <- NULL
  for (line in readLines(path, encoding = "UTF-8")) {
    if (grepl("^`{3}\\{r ", line)) {
      label <- sub("^`{3}\\{r ([^,}]+).*$", "\\1", line)
      chunks[[label]] <- character()
    } else if (identical(line, "```")) {
      label <- NULL
    } else if (!is.null(label)) {
      chunks[[label]] <- c(chunks[[label]], line)
    }
  }
  lapply(chunks, function(code) parse(text = code))
}

vignette_sources <- c(
  athena = "odbc",
  "azure-mysql" = "odbc",
  "azure-sql" = "odbc",
  cosmos = NA_character_,
  fabric = "fabricQueryR",
  databricks = "brickster",
  snowflake = "odbc",
  bigquery = NA_character_,
  "cloud-sql" = "RPostgres",
  redshift = "odbc",
  trino = "RTrino",
  dremio = "adbcdrivermanager",
  "azure-postgres" = "RPostgres",
  oracle = "odbc",
  hana = "odbc",
  singlestore = "odbc",
  "oracle-ords" = NA_character_,
  postgrest = NA_character_,
  supabase = NA_character_,
  starrocks = "odbc",
  clickhouse = NA_character_,
  postgres = "RPostgres",
  cockroachdb = "RPostgres",
  duckdb = "duckdb",
  libsql = NA_character_,
  mongodb = NA_character_,
  neo4j = NA_character_,
  cratedb = NA_character_,
  opensearch = NA_character_,
  elasticsearch = NA_character_,
  salesforce = NA_character_
)

for (source in names(vignette_sources)) {
  local({
    source_name <- source
    native_package <- vignette_sources[[source_name]]
    test_that(
      paste(
        "the",
        source_name,
        "vignette builds a complete app and waits for sign-in"
      ),
      {
        if (!is.na(native_package)) {
          skip_if_not_installed(native_package)
        }
        withr::local_envvar(playground_env())
        local_mocked_bindings(
          oauth_db_databricks_provider = playground_databricks_provider,
          .odb_postgres_runtime = function() TRUE
        )
        local_mocked_bindings(
          oauth_provider_oidc_discover = function(issuer, ...) {
            shinyOAuth::oauth_provider(
              name = "trino",
              issuer = issuer,
              auth_url = paste0(issuer, "/authorize"),
              token_url = paste0(issuer, "/token"),
              userinfo_url = paste0(issuer, "/userinfo"),
              jwks_uri = paste0(issuer, "/jwks"),
              id_token_validation = TRUE,
              userinfo_required = TRUE,
              use_nonce = TRUE
            )
          },
          .package = "shinyOAuth"
        )
        chunks <- vignette_chunks(source_name)
        envir <- new.env(parent = globalenv())
        envir$runApp <- function(app, port, launch.browser, ...) {
          expect_identical(port, 8100)
          expect_false(launch.browser)
          app
        }
        app <- eval(chunks[["app"]], envir)
        expect_s3_class(app, "shiny.appobj")
        expect_s3_class(envir$client, "shinyOAuth::OAuthClient")
        expect_identical(
          envir$client@client_id,
          playground_env()[["OAUTHDB_CLIENT_ID"]]
        )
        expect_identical(envir$client@redirect_uri, "http://localhost:8100")
        response <- envir$ui(playground_request())
        expect_equal(response$status, 200L)
        expect_match(response$content, 'id="rows"', fixed = TRUE)
        envir$oauth_module_server <- function(...) {
          list(connection = function() NULL)
        }
        shiny::testServer(envir$server, {
          session$flushReact()
          expect_error(output$rows, class = "shiny.silent.error")
        })
      }
    )
  })
}

test_that("the Cosmos guide queries with the selected visitor and clears signed-out results", {
  task_app_workers()
  withr::local_envvar(playground_env())
  app <- new.env(parent = globalenv())
  app$runApp <- function(app, ...) app
  eval(vignette_chunks("cosmos")[["app"]], app)
  calls <- new.env(parent = emptyenv())
  app$oauth_module_server <- function(id, client, ...) {
    session <- shiny::getDefaultReactiveDomain()
    a <- odb_test_authorization(session, client = client, scopes = character())
    b <- odb_test_authorization(
      session,
      id = "B",
      client = client,
      scopes = character()
    )
    selected <- shiny::reactiveVal(a$connection)
    calls$select <- function() selected(b$connection)
    list(
      connection = function() selected(),
      request_login = function() invisible(NULL),
      logout = function() selected(NULL)
    )
  }
  httr2::local_mocked_responses(function(req) {
    header <- httr2::req_get_headers(req, redacted = "reveal")$Authorization
    visitor <- sub("^.*sig=", "", utils::URLdecode(header))
    odb_http_response(paste0(
      '{"Documents":[{"id":"',
      visitor,
      '","total":10}],"_count":1}'
    ))
  })
  shiny::testServer(app$server, {
    session$flushReact()
    session$setInputs(load = 1L)
    task_app_flush(session)
    expect_match(output$rows, "fixture-A", fixed = TRUE)
    calls$select()
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(load = 2L)
    task_app_flush(session)
    expect_match(output$rows, "fixture-B", fixed = TRUE)
    expect_false(grepl("fixture-A", output$rows, fixed = TRUE))
    session$setInputs(logout = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
  })
})

test_that("the Databricks guide's Entra alternative constructs a real client", {
  withr::local_envvar(playground_env())
  envir <- new.env(parent = globalenv())
  eval(vignette_chunks("databricks")[["entra-client"]], envir)
  expect_s3_class(envir$client, "shinyOAuth::OAuthClient")
  expect_named(envir$client@token_targets, "databricks")
})

test_that("the Oracle guide's Entra alternative requests its database resource", {
  withr::local_envvar(playground_env())
  envir <- new.env(parent = globalenv())
  eval(vignette_chunks("oracle")[["entra-client"]], envir)
  expect_named(envir$client@token_targets, "oracle")
  oracle <- envir$client@token_targets$oracle
  expect_identical(oracle$resource, "api://oracle-fixture")
  expect_identical(oracle$scopes, "api://oracle-fixture/session:scope:connect")
  expect_identical(oracle$required_scopes, oracle$scopes)
  expect_identical(envir$client@token_target_default, "oracle")
})
