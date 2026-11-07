# Prepare the tiny fixture described in bigquery.md; no public datasets are scanned.
fixture <- list(
  backend = "bigquery",
  users = c(
    A = Sys.getenv("OAUTHDB_LIVE_A_IDENTITY"),
    B = Sys.getenv("OAUTHDB_LIVE_B_IDENTITY")
  ),
  validate = function(user, value) {
    is.data.frame(value) &&
      identical(value$visible_marker, paste0(user, c("-first", "-second")))
  },
  identify = function(user, native, spec) {
    native$query(
      "SELECT SESSION_USER() AS identity",
      maximum_bytes_billed = "10485760"
    )$identity[[1L]]
  },
  denied = function(user, native, spec) {
    sql <- paste(
      "SELECT * FROM",
      live_bigquery_table(live_env("OAUTHDB_BIGQUERY_FORBIDDEN_TABLE")),
      "LIMIT 1"
    )
    failure <- tryCatch(
      native$query(sql, maximum_bytes_billed = "10485760"),
      error = identity
    )
    inherits(failure, "shinyOAuthDB_request_failed") &&
      identical(failure$status, 403L)
  }
)
