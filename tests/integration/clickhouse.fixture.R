# Prepare reporting.visible_rows with server-enforced A/B row policies and
# reporting.denied_rows with no SELECT grant for either delegated JWT user.
fixture <- list(
  backend = "clickhouse",
  users = c(
    A = Sys.getenv("OAUTHDB_LIVE_A_IDENTITY"),
    B = Sys.getenv("OAUTHDB_LIVE_B_IDENTITY")
  ),
  configure = function(spec) {
    spec$native_args <- function(value) {
      list(sql = "SELECT marker FROM reporting.visible_rows ORDER BY id")
    }
    spec
  },
  validate = function(user, value) {
    is.data.frame(value) &&
      identical(value$marker, paste0(user, c("-first", "-second")))
  },
  identify = function(user, native, spec) {
    native$query("SELECT currentUser() AS identity")$identity[[1L]]
  },
  denied = function(user, native, spec) {
    failure <- tryCatch(
      native$query("SELECT * FROM reporting.denied_rows LIMIT 1"),
      error = identity
    )
    inherits(failure, "shinyOAuthDB_request_failed") &&
      identical(failure$service_code, "497")
  }
)
