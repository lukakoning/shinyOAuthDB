fixture_backend <- list(
  dbi = FALSE,
  expiry_leeway = 30,
  prepare = function() {
    deadline <- Sys.time() + 30
    repeat {
      ready <- tryCatch(httr2::resp_status(httr2::req_perform(
        httr2::request("http://localhost:13001/ready"))) == 200L, error = function(e) FALSE)
      if (ready) return(invisible(NULL))
      if (Sys.time() > deadline) stop("PostgREST readiness failed.", call. = FALSE)
      Sys.sleep(0.2)
    }
  },
  version = function() "PostgREST 16.5 / PostgreSQL 18.3",
  bind = function(authorization, username, config) {
    api <- shinyOAuthDB::oauth_db_postgrest_api(authorization,
      "https://localhost:18444", schema = "reporting", required_scopes = "database.read",
      min_valid_for = 1, ca_bundle = config$ca)
    function() api
  },
  read = function(api) api$rpc("own_rows"),
  denied = function(api, username, config) {
    other <- if (username == "alice") "bob_only" else "alice_only"
    error <- tryCatch(api$select(other), error = identity)
    denied_table <- inherits(error, "shinyOAuthDB_request_failed") && identical(error$status, 403L)
    page <- api$select("visible_rows", order = "id.asc", limit = 1L, offset = 1L, count = "exact", raw = TRUE)
    counted <- identical(httr2::resp_header(page, "Content-Range"), "1-1/2")
    page_rows <- httr2::resp_body_json(page, simplifyVector = TRUE)
    paging <- identical(page_rows$marker, paste0(username, "-visible-2"))
    empty <- api$select("visible_rows", filters = list(owner_name = paste0("eq.", if (username == "alice") "bob" else "alice")))
    payload <- "quoted ' value; -- still data"
    bound <- identical(api$rpc("echo", list(value = payload)), payload)
    write <- tryCatch(api$request("visible_rows", method = "POST",
      body = list(id = 10L, owner_name = username, marker = "must-not-write")), error = identity)
    denied_write <- inherits(write, "shinyOAuthDB_request_failed") && identical(write$status, 403L)
    list(other_table_denied = denied_table, count_header = counted, paging = paging,
      row_filter = identical(empty, data.frame()), bound_argument = bound, write_denied = denied_write)
  },
  token_denied = function(token, username, config) {
    req <- httr2::request("https://localhost:18444/visible_rows")
    req <- httr2::req_options(req, cainfo = config$ca, followlocation = FALSE)
    req <- httr2::req_headers(req, `Accept-Profile` = "reporting")
    req <- httr2::req_auth_bearer_token(req, token)
    req <- httr2::req_error(req, is_error = function(resp) FALSE)
    httr2::resp_status(httr2::req_perform(req)) == 401L
  }
)
