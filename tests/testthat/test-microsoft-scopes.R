test_that("Microsoft backends separate consent markers from operation permissions", {
  local_mocked_bindings(.odb_bind = capture_backend, .odb_require = function(...) TRUE)
  scope <- "https://example.invalid/.default"
  expect_identical(oauth_db_azure_sql(NULL, "host", "db", scopes = scope)$scopes, character())
  expect_identical(oauth_db_azure_postgres(NULL, "host", "db", "role", scopes = scope)$scopes, character())
  expect_identical(oauth_db_fabric_sql(NULL, "host", "db", scopes = scope)$scopes, character())
  expect_identical(oauth_db_fabric(NULL, "kql", scopes = scope)$scopes, character())
  expect_identical(oauth_db_databricks(NULL, "host", "wh", auth_mode = "entra", scopes = scope)$scopes,
                   character())
  permission <- "https://example.invalid/read"
  expect_identical(oauth_db_azure_sql(NULL, "host", "db", scopes = c(scope, permission))$scopes,
                   permission)
  # Native Databricks OAuth does not apply Microsoft's scope conventions.
  expect_identical(oauth_db_databricks(NULL, "host", "wh", scopes = scope)$scopes, scope)
})

test_that("PostgreSQL's default consent works with real shinyOAuth permission evidence", {
  local_mocked_bindings(.odb_require = function(...) TRUE,
    .odb_backend_postgres = function(token, ...) list(bearer = token()))
  odb_test_domain(function(session) {
    client <- oauth_db_microsoft_client("postgres", "organizations", "app", "http://localhost:8100")
    permission <- "https://ossrdbms-aad.database.windows.net/user_impersonation"
    make_token <- function(scopes) shinyOAuth::OAuthToken(
      access_token = "postgres-visitor", token_type = "Bearer",
      expires_at = as.numeric(Sys.time()) + 3600,
      granted_scopes = scopes, granted_scopes_verified = TRUE)
    token <- shiny::reactiveVal(make_token(permission))
    active <- shiny::reactiveVal(TRUE)
    grant <- getFromNamespace("OAuthConnection", "shinyOAuth")$new(
      id = "postgres", client = client,
      resolve = function() {
        if (!active()) stop("Authorization removed")
        list(client = client, token = token(), status = "active")
      },
      acquire = function(...) stop("A fresh token should not require acquisition"),
      is_current = function() active())

    expect_identical(client@token_targets$postgres$scopes,
                     "https://ossrdbms-aad.database.windows.net/.default")
    expect_false(grant$has_scopes(client@token_targets$postgres$scopes, target = "postgres"))
    con <- oauth_db_azure_postgres(grant, "host", "db", "role")
    expect_identical(con(), list(bearer = "postgres-visitor"))
    strict <- oauth_db_azure_postgres(grant, "host", "db", "role", scopes = permission)
    expect_identical(strict(), list(bearer = "postgres-visitor"))
    token(make_token(character()))
    expect_error(strict(), class = "shiny.silent.error")
    active(FALSE)
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("generic accessors do not reinterpret provider-specific scope names", {
  odb_test_domain(function(session) {
    scope <- "https://example.invalid/.default"
    auth <- odb_test_authorization(session, scopes = scope)
    token <- oauth_db_token(auth$connection, scopes = scope)
    con <- oauth_db_connect(auth$connection, connect = function(token) token,
                            scopes = scope)
    expect_identical(token(), "fixture-A")
    expect_identical(con(), "fixture-A")
    auth$token(auth$make_token("changed", permissions = character()))
    expect_error(token(), class = "shiny.silent.error")
    expect_error(con(), class = "shiny.silent.error")
  })
})
