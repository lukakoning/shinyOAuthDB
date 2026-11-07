trino_fixture_connect <- function(token, user, config) {
  DBI::dbConnect(
    RTrino::Trino(),
    host = "https://localhost",
    port = 18444L,
    catalog = "memory",
    schema = "reporting",
    user = user,
    auth = if (is.function(token)) {
      token
    } else {
      function(req) httr2::req_auth_bearer_token(req, token)
    },
    ssl_options = RTrino::trino_ssl(verify = TRUE, ca_bundle = config$ca)
  )
}


local({
  config <- list(
    issuer = "https://localhost:18443/realms/shinyoauthdb",
    ca = "/fixtures/tls/ca-cert.pem"
  )
  req <- httr2::request(paste0(config$issuer, "/protocol/openid-connect/token"))
  req <- httr2::req_body_form(
    req,
    grant_type = "client_credentials",
    client_id = "fixture-admin",
    client_secret = "fixture-admin-secret"
  )
  token <- httr2::resp_body_json(httr2::req_perform(req))$access_token
  con <- trino_fixture_connect(token, "service-account-fixture-admin", config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "CREATE SCHEMA memory.reporting")
  DBI::dbExecute(
    con,
    paste(
      "CREATE TABLE memory.reporting.visible_rows AS",
      "SELECT * FROM (VALUES (1, 'alice', 'alice-visible-1'), (2, 'alice', 'alice-visible-2'),",
      "(3, 'bob', 'bob-visible-1'), (4, 'bob', 'bob-visible-2')) AS t(id, owner_name, marker)"
    )
  )
  for (user in c("alice", "bob")) {
    DBI::dbExecute(
      con,
      paste0(
        "CREATE TABLE memory.reporting.",
        user,
        "_only AS SELECT '",
        user,
        "-private' AS marker"
      )
    )
  }
})
