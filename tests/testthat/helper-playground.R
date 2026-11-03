# Evaluate complete app definitions without starting a server or worker pool.
playground_load_example <- function(filename) {
  path <- testthat::test_path("..", "..", "playground", filename)
  if (!file.exists(path)) {
    testthat::skip("Playground examples require a source checkout.")
  }
  envir <- new.env(parent = globalenv())
  for (expr in parse(path)) {
    eval(expr, envir = envir)
    if (is.call(expr) && identical(expr[[1L]], as.name("<-")) &&
        identical(expr[[2L]], as.name("app"))) {
      stopifnot(inherits(envir$app, "shiny.appobj"))
      return(envir)
    }
  }
  stop("No Shiny app definition in ", filename, call. = FALSE)
}

playground_env <- function() {
  c(
    OAUTHDB_TENANT_ID = "11111111-1111-4111-8111-111111111111",
    OAUTHDB_CLIENT_ID = "22222222-2222-4222-8222-222222222222",
    OAUTHDB_CLIENT_SECRET = "fixture-client-secret",
    OAUTHDB_SQL_CLIENT_ID = "sql-client",
    OAUTHDB_SQL_CLIENT_SECRET = "fixture-sql-secret",
    OAUTHDB_DATABRICKS_CLIENT_ID = "databricks-client",
    OAUTHDB_DATABRICKS_CLIENT_SECRET = "fixture-databricks-secret",
    OAUTHDB_REDIRECT_URI = "http://localhost:8100",
    OAUTHDB_PORT = "8100",
    OAUTHDB_SERVER = "fixture.database.windows.net",
    OAUTHDB_DATABASE = "fixture",
    OAUTHDB_REDSHIFT_SERVER = "cluster.example.eu-west-1.redshift.amazonaws.com",
    OAUTHDB_REDSHIFT_RESOURCE = "https://redshift.example.org",
    OAUTHDB_REDSHIFT_SCOPE = "https://redshift.example.org/user_impersonation",
    OAUTHDB_TRINO_ISSUER = "https://issuer.example.org",
    OAUTHDB_TRINO_HOST = "https://trino.example.org",
    OAUTHDB_TRINO_CATALOG = "lakehouse",
    OAUTHDB_TRINO_SCHEMA = "reporting",
    OAUTHDB_POSTGRES_HOST = "fixture.postgres.database.azure.com",
    OAUTHDB_POSTGRES_ISSUER = "https://login.example.org/realms/reporting",
    OAUTHDB_POSTGRES_USER = "fixture-role",
    OAUTHDB_POSTGRES_SSLROOTCERT = "fixture-ca.pem",
    OAUTHDB_SNOWFLAKE_SERVER = "fixture.snowflakecomputing.com",
    OAUTHDB_SNOWFLAKE_SCHEMA = "PUBLIC",
    OAUTHDB_SNOWFLAKE_WAREHOUSE = "FIXTURE_WH",
    OAUTHDB_SNOWFLAKE_ROLE = "READER",
    OAUTHDB_DATABRICKS_HOST = "https://fixture.azuredatabricks.net",
    OAUTHDB_DATABRICKS_WAREHOUSE = "fixture-warehouse",
    OAUTHDB_KQL_CLUSTER = "https://fixture.kusto.fabric.microsoft.com",
    OAUTHDB_KQL_DATABASE = "fixture-kql",
    OAUTHDB_FABRIC_WORKSPACE = "33333333-3333-4333-8333-333333333333",
    OAUTHDB_FABRIC_MODEL = "44444444-4444-4444-8444-444444444444",
    OAUTHDB_GRAPHQL_API = "https://fixture.graphql.fabric.microsoft.com/v1/fixture/graphql",
    OAUTHDB_ONELAKE_ITEM = "Fixture.Lakehouse"
  )
}

playground_request <- function() {
  list(REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = "",
       HTTP_HOST = "localhost:8100", SERVER_NAME = "localhost",
       SERVER_PORT = "8100", rook.url_scheme = "http")
}

playground_databricks_provider <- function(host, token_auth_style = "public") {
  host <- paste0("https://", sub("^https://", "", host))
  shinyOAuth::oauth_provider(
    name = "databricks", auth_url = paste0(host, "/oidc/v1/authorize"),
    token_url = paste0(host, "/oidc/v1/token"),
    token_auth_style = token_auth_style, use_pkce = TRUE
  )
}

playground_fabric_app <- function() {
  path <- testthat::test_path("..", "..", "playground", "fabric")
  if (!dir.exists(path)) testthat::skip("Fabric example requires a source checkout.")
  withr::local_dir(path)
  envir <- new.env(parent = globalenv())
  sys.source("app.R", envir = envir)
  envir
}

# Preserve the native function's formals to catch incorrect example arguments.
playground_spy <- function(original, handler) {
  spy <- original
  body(spy) <- quote({
    argument_names <- setdiff(names(formals(sys.function())), "...")
    args <- mget(argument_names, envir = environment(), inherits = FALSE)
    if ("..." %in% names(formals(sys.function()))) args <- c(args, list(...))
    .handler(args)
  })
  environment(spy) <- list2env(list(.handler = handler),
                               parent = environment(original))
  spy
}

playground_module <- function(calls) {
  function(id, client, ...) {
    selected <- shiny::reactiveVal(NULL)
    sequence <- 0L
    calls$select <- function(user) {
      sequence <<- sequence + 1L
      grant_id <- paste(user, sequence, sep = "-")
      selected(list(
        id = grant_id,
        access_token = function(...) {
          stopifnot(identical(selected()$id, grant_id))
          paste0("fixture-", user)
        },
        has_scopes = function(...) identical(selected()$id, grant_id)
      ))
    }
    calls$select("A")
    list(
      connection = selected,
      request_login = function() calls$login <- calls$login + 1L,
      logout = function() selected(NULL)
    )
  }
}
