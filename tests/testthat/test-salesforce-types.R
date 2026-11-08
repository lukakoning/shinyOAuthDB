test_that("CRM numeric fields combine whole and fractional JSON values", {
  httr2::local_mocked_responses(function(req) {
    odb_http_response(
      '{"totalSize":3,"done":true,"records":[{"Id":"A","Amount":1},{"Id":"B","Amount":1.5},{"Id":"C","Amount":null}]}'
    )
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_api(
      odb_test_authorization(session, scopes = "api")$connection,
      "https://org.example"
    )
    expect_identical(
      api$query("SELECT Id, Amount FROM Opportunity")$Amount,
      c(1, 1.5, NA_real_)
    )
  })
})

test_that("Data Cloud rejects fractional or overflowing integer cells in raw results", {
  value <- "0"
  httr2::local_mocked_responses(function(req) {
    odb_http_response(paste0(
      '{"returnedRows":1,"status":{"queryId":"id","completionStatus":"Finished","rowCount":1},',
      '"metadata":[{"name":"n","type":"integer"}],"data":[[',
      value,
      ']]}'
    ))
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_data_cloud_api(
      odb_test_authorization(
        session,
        scopes = c("api", "cdp_query_api")
      )$connection,
      "https://org.example"
    )
    for (invalid in c("0.5", "2147483648", "-2147483649", '"not-a-number"')) {
      value <<- invalid
      expect_error(
        api$query("SELECT n", raw = TRUE),
        class = "shinyOAuthDB_invalid_response"
      )
    }
    value <<- "-2147483648"
    expect_identical(api$query("SELECT n")$n, -2147483648)
  })
})

test_that("Salesforce native discovery enables ID-token validation and PKCE", {
  calls <- 0L
  issuer <- "https://salesforce-discovery.example"
  metadata <- list(
    issuer = issuer,
    authorization_endpoint = paste0(issuer, "/services/oauth2/authorize"),
    token_endpoint = paste0(issuer, "/services/oauth2/token"),
    userinfo_endpoint = paste0(issuer, "/services/oauth2/userinfo"),
    jwks_uri = paste0(issuer, "/id/keys"),
    response_types_supported = list("code"),
    subject_types_supported = list("public"),
    id_token_signing_alg_values_supported = list("RS256"),
    token_endpoint_auth_methods_supported = list("client_secret_post"),
    code_challenge_methods_supported = list("S256")
  )
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    expect_identical(
      req$url,
      paste0(issuer, "/.well-known/openid-configuration")
    )
    odb_http_response(jsonlite::toJSON(metadata, auto_unbox = TRUE))
  })
  client <- oauth_db_salesforce_client(
    "app",
    "http://localhost:8100",
    "secret",
    login_url = issuer
  )
  expect_identical(calls, 1L)
  expect_true(client@provider@id_token_validation)
  expect_true(client@provider@use_pkce)
  expect_identical(client@provider@jwks_uri, paste0(issuer, "/id/keys"))
  expect_identical(client@provider@token_auth_style, "body")
})

test_that("exact Data Cloud decoding never repairs malformed numeric object keys", {
  httr2::local_mocked_responses(function(req) {
    odb_http_response(
      '{"returnedRows":1,"status":{"queryId":"id","completionStatus":"Finished","rowCount":1},"metadata":[{"name":"nested","type":"array"}],"data":[[{123:"invalid"}]]}'
    )
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_data_cloud_api(
      odb_test_authorization(
        session,
        scopes = c("api", "cdp_query_api")
      )$connection,
      "https://org.example"
    )
    expect_error(
      api$query("SELECT nested", raw = TRUE),
      class = "shinyOAuthDB_invalid_response"
    )
  })
})
