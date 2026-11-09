# Evaluate complete app definitions without starting a server or worker pool.
playground_load_example <- function(filename) {
  task_app_workers(envir = parent.frame())
  path <- testthat::test_path("..", "..", "playground", filename)
  if (!file.exists(path)) {
    testthat::skip("Playground examples require a source checkout.")
  }
  envir <- new.env(parent = globalenv())
  for (expr in parse(path)) {
    eval(expr, envir = envir)
    if (
      is.call(expr) &&
        identical(expr[[1L]], as.name("<-")) &&
        identical(expr[[2L]], as.name("app"))
    ) {
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
    OAUTHDB_ATHENA_ISSUER = "https://issuer.example.org/realms/athena",
    OAUTHDB_ATHENA_SCOPES = "database.read",
    OAUTHDB_ATHENA_WORKGROUP_ARN = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
    OAUTHDB_ATHENA_APPLICATION_ROLE_ARN = "arn:aws:iam::123456789012:role/AthenaApplication",
    OAUTHDB_ATHENA_OUTPUT = "s3://query-results/reporting/",
    OAUTHDB_SERVER = "fixture.database.windows.net",
    OAUTHDB_DATABASE = "fixture",
    OAUTHDB_REDSHIFT_SERVER = "cluster.example.eu-west-1.redshift.amazonaws.com",
    OAUTHDB_REDSHIFT_RESOURCE = "https://redshift.example.org",
    OAUTHDB_REDSHIFT_SCOPE = "https://redshift.example.org/user_impersonation",
    OAUTHDB_TRINO_ISSUER = "https://issuer.example.org",
    OAUTHDB_DREMIO_ISSUER = "https://issuer.example.org",
    OAUTHDB_DREMIO_SCOPE = "database.read",
    OAUTHDB_DREMIO_HOST = "dremio.example.org",
    OAUTHDB_DUCKDB_ISSUER = "https://issuer.example.org",
    OAUTHDB_LIBSQL_ISSUER = "https://issuer.example.org",
    OAUTHDB_MONGODB_ISSUER = "https://issuer.example.org",
    OAUTHDB_MONGODB_URL = "mongodb://mongo.example.org",
    OAUTHDB_MONGODB_DATABASE = "reporting",
    OAUTHDB_NEO4J_ISSUER = "https://issuer.example.org",
    OAUTHDB_NEO4J_URL = "https://graph.example.org",
    OAUTHDB_NEO4J_DATABASE = "neo4j",
    OAUTHDB_LIBSQL_URL = "libsql://db.example.org",
    OAUTHDB_LIBSQL_AUDIENCE = "libsql-fixture",
    OAUTHDB_CRATEDB_ISSUER = "https://issuer.example.org",
    OAUTHDB_OPENSEARCH_ISSUER = "https://issuer.example.org",
    OAUTHDB_ELASTICSEARCH_ISSUER = "https://issuer.example.org",
    OAUTHDB_ELASTICSEARCH_URL = "https://search.example.org",
    OAUTHDB_ELASTICSEARCH_REALM_SECRET = "fixture-realm-secret",
    OAUTHDB_TRINO_HOST = "https://trino.example.org",
    OAUTHDB_TRINO_CATALOG = "lakehouse",
    OAUTHDB_TRINO_SCHEMA = "reporting",
    OAUTHDB_POSTGREST_ISSUER = "https://issuer.example.org",
    OAUTHDB_POSTGREST_URL = "https://data.example.org",
    OAUTHDB_SUPABASE_URL = "https://project.example.org",
    OAUTHDB_SUPABASE_KEY = "sb_publishable_fixture",
    OAUTHDB_SUPABASE_ISSUER = "https://issuer.example.org",
    OAUTHDB_STARROCKS_ISSUER = "https://issuer.example.org",
    OAUTHDB_STARROCKS_SERVER = "starrocks.example.org",
    OAUTHDB_STARROCKS_DRIVER = "MySQL ODBC 9.2 Unicode Driver",
    OAUTHDB_STARROCKS_SSL_CA = "fixture-ca.pem",
    OAUTHDB_CLICKHOUSE_ISSUER = "https://issuer.example.org",
    OAUTHDB_CLICKHOUSE_URL = "https://clickhouse.example.org:8443",
    OAUTHDB_POSTGRES_HOST = "fixture.postgres.database.azure.com",
    OAUTHDB_POSTGRES_ISSUER = "https://login.example.org/realms/reporting",
    OAUTHDB_POSTGRES_USER = "fixture-role",
    OAUTHDB_COCKROACHDB_HOST = "sql.example.org",
    OAUTHDB_COCKROACHDB_DATABASE = "reporting",
    OAUTHDB_COCKROACHDB_ISSUER = "https://issuer.example.org",
    OAUTHDB_COCKROACHDB_AUDIENCE = "shiny-reporting",
    OAUTHDB_POSTGRES_SSLROOTCERT = "fixture-ca.pem",
    OAUTHDB_ORACLE_RESOURCE = "api://oracle-fixture",
    OAUTHDB_ORACLE_ISSUER = "https://issuer.example.org/realms/oracle",
    OAUTHDB_ORACLE_SCOPE = "database.read",
    OAUTHDB_ORACLE_HOST = "oracle.example.org",
    OAUTHDB_HANA_ISSUER = "https://issuer.example.org/realms/hana",
    OAUTHDB_HANA_SCOPE = "database.read",
    OAUTHDB_HANA_SERVER = "hana.example.org",
    OAUTHDB_HANA_PORT = "443",
    OAUTHDB_HANA_DRIVER = "HDBODBC",
    OAUTHDB_SINGLESTORE_ISSUER = "https://issuer.example.org/realms/singlestore",
    OAUTHDB_SINGLESTORE_SCOPE = "database.read",
    OAUTHDB_SINGLESTORE_SERVER = "sql.example.org",
    OAUTHDB_SINGLESTORE_SSL_CA = "fixture-ca.pem",
    OAUTHDB_ORACLE_SERVICE = "reporting.example.org",
    OAUTHDB_ORACLE_DRIVER = "Oracle driver",
    OAUTHDB_ORDS_ISSUER = "https://issuer.example.org/realms/ords",
    OAUTHDB_ORDS_SCOPE = "reports.read",
    OAUTHDB_ORDS_URL = "https://data.example.org/ords/reports",
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
  list(
    REQUEST_METHOD = "GET",
    PATH_INFO = "/",
    QUERY_STRING = "",
    HTTP_HOST = "localhost:8100",
    SERVER_NAME = "localhost",
    SERVER_PORT = "8100",
    rook.url_scheme = "http"
  )
}

playground_databricks_provider <- function(host, token_auth_style = "public") {
  host <- paste0("https://", sub("^https://", "", host))
  shinyOAuth::oauth_provider(
    name = "databricks",
    auth_url = paste0(host, "/oidc/v1/authorize"),
    token_url = paste0(host, "/oidc/v1/token"),
    token_auth_style = token_auth_style,
    use_pkce = TRUE
  )
}

playground_fabric_app <- function() {
  task_app_workers(envir = parent.frame())
  path <- testthat::test_path("..", "..", "playground", "fabric")
  if (!dir.exists(path)) {
    testthat::skip("Fabric example requires a source checkout.")
  }
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
    if ("..." %in% names(formals(sys.function()))) {
      args <- c(args, list(...))
    }
    .handler(args)
  })
  environment(spy) <- list2env(
    list(.handler = handler),
    parent = environment(original)
  )
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
        has_scopes = function(...) identical(selected()$id, grant_id),
        identity = function(claims = c("iss", "sub"), userinfo = character()) {
          stopifnot(identical(selected()$id, grant_id))
          values <- list(
            iss = "https://issuer.example.org",
            sub = paste0("subject-", user),
            preferred_username = user
          )
          list(
            id_token_claims = values[intersect(claims, names(values))],
            userinfo = list()
          )
        }
      ))
    }
    calls$select("A")
    list(
      connection = selected,
      request_login = function() {
        calls$login <- calls$login + 1L
      },
      logout = function() selected(NULL)
    )
  }
}
