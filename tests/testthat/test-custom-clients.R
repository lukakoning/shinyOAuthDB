test_that("ordinary Microsoft clients retain explicit scope and target configuration", {
  local_mocked_bindings(.odb_require = function(...) TRUE,
    .odb_backend_sql = function(token, ...) list(bearer = token()))
  provider <- shinyOAuth::oauth_provider_microsoft(
    tenant = "organizations", userinfo_required = FALSE)
  permission <- "https://database.windows.net//user_impersonation"
  for (target in list(NULL, "reporting")) odb_test_domain(function(session) {
    client <- shinyOAuth::oauth_client(provider, "app",
      redirect_uri = "http://localhost:8100",
      scopes = c("openid", "profile", "offline_access", permission),
      required_scopes = if (is.null(target)) permission else character(),
      token_targets = if (is.null(target)) list() else list(reporting = list(
        resource = "https://database.windows.net/", scopes = permission, required_scopes = permission)),
      token_target_default = if (is.null(target)) character() else "reporting")
    auth <- odb_test_authorization(session, scopes = permission, client = client)
    con <- oauth_db_azure_sql(auth$connection, "server", "Reporting", target = target)
    expect_identical(con(), list(bearer = "fixture-A"))
    # The preset's target name must not silently fall back to this client.
    wrong <- oauth_db_azure_sql(auth$connection, "server", "Reporting")
    expect_error(wrong(), class = "shinyOAuth_access_error")
    auth$token(auth$make_token("denied", character()))
    expect_error(con(), "client's requested and required scopes", fixed = TRUE)
  })
})

test_that("untargeted Microsoft default consent needs no duplicate helper scope policy", {
  local_mocked_bindings(.odb_require = function(...) TRUE,
    .odb_backend_sql = function(token, ...) list(bearer = token()))
  odb_test_domain(function(session) {
    provider <- shinyOAuth::oauth_provider_microsoft(
      tenant = "organizations", userinfo_required = FALSE)
    client <- shinyOAuth::oauth_client(provider, "app",
      redirect_uri = "http://localhost:8100",
      scopes = c("openid", "profile", "offline_access",
        "https://database.windows.net//.default"))
    auth <- odb_test_authorization(session, client = client, scopes = "user_impersonation")
    strict <- oauth_db_azure_sql(auth$connection, "server", "Reporting", target = NULL,
      required_scopes = "https://database.windows.net//user_impersonation")
    expect_error(strict(), class = "shiny.silent.error")
    con <- oauth_db_azure_sql(auth$connection, "server", "Reporting",
      target = NULL)
    expect_identical(con(), list(bearer = "fixture-A"))
    auth$current(FALSE)
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("SQL-scoped Databricks clients work with native DBI and REST calls", {
  skip_if_not_installed("brickster")
  calls <- list()
  local_mocked_bindings(db_sql_query = function(statement, token, ...) {
    calls[[length(calls) + 1L]] <<- list(statement = statement, token = token)
    data.frame(database_user = "visitor")
  }, .package = "brickster")
  odb_test_domain(function(session) {
    provider <- shinyOAuth::oauth_provider("custom-workspace",
      "https://workspace.example/authorize", "https://workspace.example/token",
      token_auth_style = "public")
    client <- oauth_db_databricks_client(client_id = "app",
      redirect_uri = "http://localhost:8100", provider = provider,
      scopes = c("openid", "profile", "email", "offline_access", "sql"), required_scopes = "sql")
    auth <- odb_test_authorization(session, scopes = "sql", client = client)
    con <- oauth_db_databricks(auth$connection, "workspace.example", "wh")
    bearer <- oauth_db_token(auth$connection, required_scopes = "sql")
    connection <- con()
    statement <- "SELECT current_user() AS database_user"
    expect_identical(DBI::dbGetQuery(connection, statement),
      data.frame(database_user = "visitor"))
    expect_identical(brickster::db_sql_query(host = "workspace.example",
      warehouse_id = "wh", statement = statement, token = bearer()),
      data.frame(database_user = "visitor"))
    expect_identical(calls[[2L]], list(statement = statement, token = "fixture-A"))
    expect_identical(calls[[3L]], calls[[2L]])
    broader <- oauth_db_databricks(auth$connection, "workspace.example", "wh", required_scopes = "all-apis")
    expect_error(broader(), class = "shiny.silent.error")
    auth$token(auth$make_token("denied", character()))
    expect_error(con(), class = "shiny.silent.error")
    expect_error(bearer(), class = "shiny.silent.error")
  })
})
