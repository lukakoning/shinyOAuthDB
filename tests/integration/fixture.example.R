# Copy outside Git, or into a locally ignored file. This defines no credentials.
# Prepare a database fixture that returns A-only / B-only rows through native
# row-level security or separate grants. Set its exact trusted read query here.
fixture <- list(
  backend = "azure-sql",
  configure = function(spec) {
    spec$native_args <- function(value) list(
      statement = "SELECT visible_marker FROM dbo.OAuthDBAcceptance ORDER BY visible_marker"
    )
    spec
  },
  validate = function(user, value) {
    is.data.frame(value) &&
      identical(as.character(value$visible_marker), paste0(user, c("-first", "-second")))
  }
)
