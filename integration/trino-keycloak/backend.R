trino_fixture_connect <- function(token, user, config) {
  DBI::dbConnect(RTrino::Trino(), host = "https://localhost", port = 18444L,
    catalog = "memory", schema = "reporting", user = user,
    auth = if (is.function(token)) token else function(req) httr2::req_auth_bearer_token(req, token),
    ssl_options = RTrino::trino_ssl(verify = TRUE, ca_bundle = config$ca))
}

fixture_backend <- list(
  dbi = TRUE,
  expiry_leeway = 0,
  prepare = function() {
    config <- fixture_config()
    req <- httr2::request(paste0(config$issuer, "/protocol/openid-connect/token"))
    req <- httr2::req_body_form(req, grant_type = "client_credentials",
      client_id = "fixture-admin", client_secret = "fixture-admin-secret")
    token <- httr2::resp_body_json(httr2::req_perform(req))$access_token
    con <- trino_fixture_connect(token, "service-account-fixture-admin", config)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbExecute(con, "CREATE SCHEMA memory.reporting")
    DBI::dbExecute(con, paste("CREATE TABLE memory.reporting.visible_rows AS",
      "SELECT * FROM (VALUES (1, 'alice', 'alice-visible-1'), (2, 'alice', 'alice-visible-2'),",
      "(3, 'bob', 'bob-visible-1'), (4, 'bob', 'bob-visible-2')) AS t(id, owner_name, marker)"))
    for (user in c("alice", "bob")) {
      DBI::dbExecute(con, paste0("CREATE TABLE memory.reporting.", user,
        "_only AS SELECT '", user, "-private' AS marker"))
    }
  },
  version = function() list(server = "Trino 484", RTrino = as.character(packageVersion("RTrino"))),
  bind = function(authorization, username, config) {
    shinyOAuthDB::oauth_db_trino(authorization, "https://localhost:18444",
      "memory", "reporting", user = username, ca_bundle = config$ca,
      required_scopes = "database.read", min_valid_for = 1, timeout = 20)
  },
  read = function(con) DBI::dbGetQuery(con,
    "SELECT current_user AS database_user, marker FROM memory.reporting.visible_rows ORDER BY id"),
  denied = function(con, username, config) {
    other <- if (username == "alice") "bob" else "alice"
    error <- tryCatch(DBI::dbGetQuery(con, paste0("SELECT * FROM memory.reporting.", other, "_only")), error = identity)
    table_denied <- inherits(error, "error") && grepl("Access Denied", conditionMessage(error), fixed = TRUE)
    impersonation <- tryCatch({
      spoof <- trino_fixture_connect(con@auth, other, config)
      tryCatch(DBI::dbGetQuery(spoof, "SELECT current_user"), finally = DBI::dbDisconnect(spoof))
    }, error = identity)
    spoof_denied <- inherits(impersonation, "error") &&
      grepl("Access Denied", conditionMessage(impersonation), fixed = TRUE)
    cursor <- DBI::dbSendQuery(con, paste("SELECT marker FROM memory.reporting.visible_rows",
      "CROSS JOIN UNNEST(sequence(1, 1024)) AS t(i)"))
    on.exit(DBI::dbClearResult(cursor), add = TRUE)
    first <- DBI::dbFetch(cursor, n = 1L)
    rest <- DBI::dbFetch(cursor)
    list(other_table_denied = table_denied, impersonation_denied = spoof_denied,
      native_fetch = nrow(first) == 1L && nrow(rest) == 2047L &&
        all(startsWith(c(first$marker, rest$marker), username)))
  },
  token_denied = function(token, username, config) {
    error <- tryCatch({
      con <- trino_fixture_connect(token, username, config)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      DBI::dbGetQuery(con, "SELECT current_user")
    }, error = identity)
    inherits(error, "httr2_http_401")
  }
)
