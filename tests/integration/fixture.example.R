# Copy outside Git, or into a locally ignored file. This defines no credentials.
# Prepare a database fixture that returns A-only / B-only rows through native
# row-level security or separate grants. Set its exact trusted read query here.
fixture <- list(
  backend = "azure-sql",
  users = c(A = "user-a@example.org", B = "user-b@example.org"),
  identify = function(user, native, spec) {
    as.character(DBI::dbGetQuery(
      native,
      "SELECT ORIGINAL_LOGIN() AS identity"
    )$identity[[1L]])
  },
  denied = function(user, native, spec) {
    failure <- tryCatch(
      DBI::dbGetQuery(native, "SELECT * FROM dbo.OAuthDBForbidden"),
      error = identity
    )
    inherits(failure, "error") &&
      grepl("permission|denied", conditionMessage(failure), ignore.case = TRUE)
  },
  configure = function(spec) {
    spec$native_args <- function(value) {
      list(
        statement = "SELECT visible_marker FROM dbo.OAuthDBAcceptance ORDER BY visible_marker"
      )
    }

    spec
  },

  validate = function(user, value) {
    is.data.frame(value) &&
      identical(
        as.character(value$visible_marker),
        paste0(user, c("-first", "-second"))
      )
  }
)
