test_that("source OAuth plans union compatible targets and preserve literal resources", {
  sources <- list(
    sql = oauth_db_azure_sql("example.database.windows.net", "db"),
    dax = oauth_db_fabric(
      "dax",
      workspace_id = "workspace",
      dataset_id = "dataset"
    ),
    graphql = oauth_db_fabric(
      "graphql",
      api = "https://example.graphql.fabric.microsoft.com/graphql"
    )
  )
  plan <- oauth_db_auth_plan(sources, default_source = "dax")

  expect_identical(plan$default_token_target, "power_bi")
  expect_identical(
    plan$token_targets$sql$resource,
    "https://database.windows.net/"
  )
  expect_identical(
    plan$token_targets$sql$scopes,
    "https://database.windows.net//user_impersonation"
  )
  expect_setequal(
    plan$token_targets$power_bi$scopes,
    c(sources$dax$auth$scopes, sources$graphql$auth$scopes)
  )

  client <- oauth_db_microsoft_client(
    sources,
    "organizations",
    "registered-id",
    redirect_uri = "http://localhost:8100",
    default_source = "dax"
  )

  expect_identical(client@default_token_target, "power_bi")
  expect_identical(
    client@token_targets$sql$resource,
    "https://database.windows.net/"
  )
  expect_identical(client@provider@userinfo_required, FALSE)

  public_client <- oauth_db_microsoft_client(
    sources,
    "organizations",
    "registered-id",
    client_secret = "",
    redirect_uri = "http://localhost:8100"
  )

  expect_length(public_client@client_secret, 0L)
  expect_error(
    oauth_db_microsoft_client(
      sources,
      "organizations",
      "registered-id",
      redirect_uri = "http://localhost:8100",
      provider = NULL
    ),
    "cannot override"
  )
})

test_that("different provider registrations and incompatible Microsoft consent stay explicit", {
  sql <- oauth_db_azure_sql("example.database.windows.net", "db")
  postgres <- oauth_db_azure_postgres(
    "example.postgres.database.azure.com",
    "db",
    "role"
  )

  expect_error(
    oauth_db_auth_plan(list(sql = sql, postgres = postgres)),
    class = "shinyOAuthDB_incompatible_authentication"
  )

  conflict <- oauth_db_custom(
    "fixture",
    connect = function(config, token_provider) NULL,
    target = "sql",
    resource = "https://other.invalid",
    scopes = "https://other.invalid/read",
    provider_family = "microsoft"
  )

  expect_error(
    oauth_db_auth_plan(list(sql = sql, conflict = conflict)),
    "same literal"
  )

  mixed <- list(
    sql = sql,
    databricks = oauth_db_databricks("example.cloud.databricks.com")
  )

  expect_setequal(
    names(oauth_db_auth_plan(mixed)$provider_groups),
    c("microsoft", "databricks")
  )
  expect_error(
    oauth_db_microsoft_client(
      mixed,
      "organizations",
      "id",
      redirect_uri = "http://localhost:8100"
    ),
    class = "shinyOAuthDB_incompatible_authentication"
  )
  expect_error(
    oauth_db_auth_plan(list(sql = sql), default_source = "missing"),
    "default_source"
  )
})

test_that("native Snowflake client delegates login to shinyOAuth with account endpoints", {
  source <- oauth_db_snowflake(
    "account.snowflakecomputing.com",
    "DB",
    "PUBLIC",
    "WH",
    "READER",
    auth_mode = "snowflake_oauth",
    scopes = "session:role:READER"
  )
  client <- oauth_db_snowflake_client(
    source,
    "registered-id",
    "fixture-secret",
    "http://localhost:8100"
  )

  expect_identical(
    client@provider@token_url,
    "https://account.snowflakecomputing.com/oauth/token-request"
  )
  expect_setequal(client@scopes, c("session:role:READER", "refresh_token"))
  expect_true(client@provider@use_pkce)
  expect_false(client@provider@id_token_validation)
  expect_false(grepl(
    "fixture-secret",
    paste(capture.output(print(client)), collapse = ""),
    fixed = TRUE
  ))
})
