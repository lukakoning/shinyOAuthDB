test_that("Microsoft convenience configures native targets without source objects", {
  client <- oauth_db_microsoft_client(c("sql", "dax", "graphql"), "organizations", "app",
                                      "http://localhost:8100")
  expect_s3_class(client, "shinyOAuth::OAuthClient")
  expect_equal(client@token_target_default, "sql")
  expect_equal(client@token_targets$sql$resource, "https://database.windows.net/")
  expect_equal(client@token_targets$sql$scopes, "https://database.windows.net//user_impersonation")
  expect_length(client@token_targets$power_bi$scopes, 2L)
  expect_length(client@client_secret, 0L)
  expect_error(oauth_db_microsoft_client(c("sql", "postgres"), "organizations", "app",
                                        "http://localhost:8100"), "cannot mix .default")
  expect_error(oauth_db_microsoft_client("made-up", "organizations", "app",
                                        "http://localhost:8100"), "supported")
})

test_that("Microsoft presets accept native providers and derive consent from custom targets", {
  provider <- shinyOAuth::oauth_provider_microsoft(
    name = "my-tenant", tenant = "organizations", userinfo_required = FALSE)
  targets <- list(reporting = list(resource = "https://database.windows.net/",
    scopes = "https://database.windows.net//user_impersonation"))
  client <- oauth_db_microsoft_client(
    services = stop("Do not evaluate replaced defaults"),
    client_id = "custom-app", redirect_uri = "http://localhost:8100",
    provider = provider, token_targets = targets,
    scope_validation = "strict", label = "Reporting database")
  expect_identical(client@provider, provider)
  expect_identical(client@token_targets, targets)
  expect_identical(client@token_target_default, "reporting")
  expect_identical(client@scopes, c("openid", "profile", "offline_access",
    targets$reporting$scopes))
  expect_identical(client@scope_validation, "strict")
  expect_identical(client@label, "Reporting database")

  single <- oauth_db_microsoft_client(client_id = "custom-app",
    redirect_uri = "http://localhost:8100", provider = provider,
    token_targets = list(), scopes = targets$reporting$scopes,
    resource = "https://database.windows.net/", required_scopes = targets$reporting$scopes)
  expect_identical(single@token_targets, list())
  expect_identical(single@token_target_default, character())
  expect_identical(single@scopes, targets$reporting$scopes)
  expect_identical(single@required_scopes, targets$reporting$scopes)
  expect_identical(single@resource, "https://database.windows.net/")

  # Invalid replacements are still checked by the native constructor.
  expect_error(oauth_db_microsoft_client(client_id = "app",
    redirect_uri = "http://localhost:8100", provider = provider,
    token_targets = targets, scopes = "openid"), "Target scopes")
})

test_that("Microsoft presets let callers select another default target", {
  client <- oauth_db_microsoft_client(c("sql", "kql"), "organizations", "app",
    "http://localhost:8100", token_target_default = "kusto")
  expect_identical(client@token_target_default, "kusto")
  expect_setequal(names(client@token_targets), c("sql", "kusto"))
})

test_that("Databricks provider overrides bypass discovery and preserve client settings", {
  provider <- shinyOAuth::oauth_provider(
    "databricks", "https://example.com/authorize", "https://example.com/token",
    token_auth_style = "public")
  local_mocked_bindings(.odb_databricks_provider = function(...) stop("Unexpected discovery"))
  client <- oauth_db_databricks_client(client_id = "app",
    redirect_uri = "http://localhost:8100", provider = provider,
    scopes = c("sql", "offline_access"), label = "SQL only")
  expect_identical(client@provider, provider)
  expect_identical(client@scopes, c("sql", "offline_access"))
  expect_identical(client@label, "SQL only")
})

test_that("Databricks default provider uses native public-client secret conventions", {
  local_mocked_bindings(oauth_db_databricks_provider = playground_databricks_provider)
  for (secret in list(NULL, "", character())) {
    client <- oauth_db_databricks_client("https://example.com", "app",
      "http://localhost:8100", client_secret = secret)
    expect_identical(client@provider@token_auth_style, "public")
    expect_length(client@client_secret, 0L)
  }
  client <- oauth_db_databricks_client("https://example.com", "app",
    "http://localhost:8100", client_secret = "secret")
  expect_identical(client@provider@token_auth_style, "header")
})

test_that("Databricks discovery belongs here and uses only shinyOAuth's public API", {
  captured <- new.env(parent = emptyenv())
  captured$calls <- 0L
  local_mocked_bindings(oauth_provider_oidc_discover = function(issuer, ...) {
    captured$calls <- captured$calls + 1L
    captured$args <- c(list(issuer = issuer), list(...))
    playground_databricks_provider("https://workspace.example", token_auth_style = "public")
  }, .package = "shinyOAuth")
  provider <- oauth_db_databricks_provider("https://Workspace.Example/", "public", name = "analytics")
  expect_s3_class(provider, "shinyOAuth::OAuthProvider")
  expect_identical(captured$args$issuer, "https://workspace.example/oidc/.well-known/openid-configuration")
  expect_identical(captured$args$name, "analytics")
  expect_identical(captured$args$token_auth_style, "public")
  expect_true(captured$args$use_pkce)
  expect_true(captured$args$use_nonce)
  expect_true(captured$args$id_token_validation)
  expect_false(captured$args$userinfo_required)
  expect_error(oauth_db_databricks_provider("http://workspace.example"), "HTTPS origin")
  expect_error(oauth_db_databricks_provider("https://workspace.example/path"), "without a path")
  expect_error(oauth_db_databricks_provider("workspace.example", "public", "unnamed"),
    class = "shinyOAuthDB_invalid_configuration")
  expect_error(oauth_db_databricks_provider("workspace.example", "public", name = "one", name = "two"),
    class = "shinyOAuthDB_invalid_configuration")
  expect_identical(captured$calls, 1L)
})

test_that("Snowflake provider presets compose directly with native clients", {
  provider <- oauth_db_snowflake_provider("account.snowflakecomputing.com",
    name = "analytics", token_auth_style = "body",
    extra_auth_params = list(prompt = "consent"), use_nonce = NULL)
  expect_s3_class(provider, "shinyOAuth::OAuthProvider")
  expect_identical(provider@name, "analytics")
  expect_identical(provider@token_auth_style, "body")
  expect_identical(provider@extra_auth_params, list(prompt = "consent"))
  expect_identical(provider@token_url, "https://account.snowflakecomputing.com/oauth/token-request")
  client <- shinyOAuth::oauth_client(provider, "app", client_secret = "secret",
    redirect_uri = "http://localhost:8100", scopes = "session:role:READER")
  expect_identical(client@provider, provider)

  custom <- oauth_db_snowflake_client(client_id = "app", client_secret = "secret",
    redirect_uri = "http://localhost:8100", provider = provider,
    scopes = "session:role:ANALYST", scope_validation = "strict")
  expect_identical(custom@provider, provider)
  expect_identical(custom@scopes, "session:role:ANALYST")
  expect_identical(custom@scope_validation, "strict")
  expect_error(oauth_db_snowflake_provider("account.snowflakecomputing.com",
    "unnamed"), "unique names")
  expect_error(oauth_db_snowflake_provider("account.snowflakecomputing.com",
    name = "a", name = "b"), "unique names")
})

test_that("Snowflake convenience leaves login to shinyOAuth", {
  client <- oauth_db_snowflake_client("account.snowflakecomputing.com", "app", "secret",
                                      "http://localhost:8100", "READER")
  expect_s3_class(client, "shinyOAuth::OAuthClient")
  expect_equal(client@scopes, c("session:role:READER", "refresh_token"))
  expect_equal(client@provider@auth_url, "https://account.snowflakecomputing.com/oauth/authorize")
})
