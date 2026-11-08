test_that("Microsoft backends separate consent markers from operation permissions", {
  local_mocked_bindings(
    .odb_bind = capture_backend,
    .odb_require = function(...) TRUE
  )
  scope <- "https://example.invalid/.default"
  expect_identical(
    oauth_db_azure_sql(
      NULL,
      "host",
      "db",
      required_scopes = scope
    )$required_scopes,
    character()
  )
  expect_identical(
    oauth_db_azure_postgres(
      NULL,
      "host",
      "db",
      "role",
      required_scopes = scope
    )$required_scopes,
    character()
  )
  expect_identical(
    oauth_db_fabric_sql(
      NULL,
      "host",
      "db",
      required_scopes = scope
    )$required_scopes,
    character()
  )
  expect_identical(
    oauth_db_fabric(NULL, "kql", required_scopes = scope)$required_scopes,
    character()
  )
  expect_identical(
    oauth_db_databricks(
      NULL,
      "host",
      "wh",
      auth_mode = "entra",
      required_scopes = scope
    )$required_scopes,
    character()
  )
  permission <- "https://example.invalid/read"
  expect_identical(
    oauth_db_azure_sql(
      NULL,
      "host",
      "db",
      required_scopes = c(scope, permission)
    )$required_scopes,
    permission
  )
  # Native Databricks OAuth does not apply Microsoft's scope conventions.
  expect_identical(
    oauth_db_databricks(
      NULL,
      "host",
      "wh",
      required_scopes = scope
    )$required_scopes,
    scope
  )
})

test_that("PostgreSQL's default consent works with real shinyOAuth permission evidence", {
  local_mocked_bindings(
    .odb_require = function(...) TRUE,
    .odb_backend_postgres = function(token, ...) list(bearer = token())
  )
  odb_test_domain(function(session) {
    client <- oauth_db_microsoft_client(
      "postgres",
      "organizations",
      "app",
      "http://localhost:8100"
    )
    permission <- "https://ossrdbms-aad.database.windows.net/user_impersonation"
    make_token <- function(scopes) {
      shinyOAuth::OAuthToken(
        access_token = "postgres-visitor",
        token_type = "Bearer",
        expires_at = as.numeric(Sys.time()) + 3600,
        granted_scopes = scopes,
        granted_scopes_verified = TRUE
      )
    }
    token <- shiny::reactiveVal(make_token(permission))
    active <- shiny::reactiveVal(TRUE)
    grant <- getFromNamespace("OAuthConnection", "shinyOAuth")$new(
      id = "postgres",
      client = client,
      resolve = function() {
        if (!active()) {
          getFromNamespace("connection_access_error", "shinyOAuth")(
            "authorization_unavailable"
          )
        }
        list(client = client, token = token(), status = "active")
      },
      acquire = function(...) {
        stop("A fresh token should not require acquisition")
      },
      is_current = function() active()
    )

    expect_identical(
      client@token_targets$postgres$scopes,
      "https://ossrdbms-aad.database.windows.net/.default"
    )
    expect_false(grant$has_scopes(
      client@token_targets$postgres$scopes,
      target = "postgres"
    ))
    con <- oauth_db_azure_postgres(grant, "host", "db", "role")
    expect_identical(con(), list(bearer = "postgres-visitor"))
    strict <- oauth_db_azure_postgres(
      grant,
      "host",
      "db",
      "role",
      required_scopes = permission
    )
    expect_identical(strict(), list(bearer = "postgres-visitor"))
    token(make_token(character()))
    expect_error(strict(), class = "shiny.silent.error")
    active(FALSE)
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("PostgreSQL composes with every Microsoft service in either order", {
  targets <- c(
    sql = "sql",
    fabric = "fabric",
    kql = "kusto",
    dax = "power_bi",
    graphql = "power_bi",
    onelake = "storage",
    databricks_entra = "databricks"
  )
  permission <- "https://ossrdbms-aad.database.windows.net/user_impersonation"
  for (service in names(targets)) {
    for (services in list(c("postgres", service), c(service, "postgres"))) {
      client <- oauth_db_microsoft_client(
        services,
        "organizations",
        "app",
        "http://localhost:8100"
      )
      expect_identical(
        client@token_target_default,
        if (services[[1L]] == "postgres") "postgres" else targets[[service]]
      )
      expect_setequal(
        names(client@token_targets),
        c("postgres", targets[[service]])
      )
      expect_identical(client@token_targets$postgres$scopes, permission)
      expect_identical(
        client@token_targets$postgres$required_scopes,
        permission
      )
      expect_true(permission %in% client@scopes)
      expect_false(any(endsWith(client@scopes, "/.default")))
    }
  }
  client <- oauth_db_microsoft_client(
    c("postgres", names(targets)),
    "organizations",
    "app",
    "http://localhost:8100"
  )
  expect_identical(client@token_target_default, "postgres")
  expect_length(client@token_targets$power_bi$scopes, 2L)
})

test_that("mixed Microsoft clients enforce PostgreSQL permissions independently", {
  local_mocked_bindings(
    .odb_require = function(...) TRUE,
    .odb_backend_postgres = function(token, ...) list(bearer = token())
  )
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(
      session,
      services = c("postgres", "sql")
    )
    con <- oauth_db_azure_postgres(auth$connection, "host", "db", "role")
    sql <- oauth_db_token(auth$connection, target = "sql")
    expect_identical(con(), list(bearer = "A-postgres"))
    expect_identical(sql(), "A-sql")
    values <- auth$tokens()
    values$postgres <- auth$make_token("postgres", scopes = character())
    auth$tokens(values)
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(sql(), "A-sql")
    values$postgres <- auth$make_token("postgres")
    auth$tokens(values)
    expect_identical(con(), list(bearer = "A-postgres"))
  })
})

test_that("generic accessors do not reinterpret provider-specific scope names", {
  odb_test_domain(function(session) {
    scope <- "https://example.invalid/.default"
    auth <- odb_test_authorization(session, scopes = scope)
    token <- oauth_db_token(auth$connection, required_scopes = scope)
    con <- oauth_db_connect(
      auth$connection,
      connect = function(token) token,
      required_scopes = scope
    )
    expect_identical(token(), "fixture-A")
    expect_identical(con(), "fixture-A")
    auth$token(auth$make_token("changed", permissions = character()))
    expect_error(token(), class = "shiny.silent.error")
    expect_error(con(), class = "shiny.silent.error")
  })
})
