# Snowflake: why skiLift is deferred

shinyOAuthDB uses DBI and odbc for Snowflake. The source review on
1 November 2026 found that skiLift's token handling didn't yet fit
separate user sign-ins in a Shiny app.

skiLift's SQL API could remove the ODBC driver requirement, but the
review found these issues:

- An explicit `token` was treated as a programmatic access token even with
  `authenticator = "oauth"`. See [authentication resolution](https://github.com/posit-dev/skiLift/blob/main/R/auth.R).
- Refresh could read Workspace credentials from the hosting environment.
  See [token refresh](https://github.com/posit-dev/skiLift/blob/main/R/api.R).
- The constructor accepted a token string but no external token callback.
  See the [constructor](https://github.com/posit-dev/skiLift/blob/main/R/driver.R).

Reconsider skiLift when it accepts an external OAuth token with the correct
type and provides a supported way to renew it or rebuild the connection
without changing the user. Its
[transaction support](https://github.com/posit-dev/skiLift/blob/main/R/transactions.R)
would also need documenting.

These are source-review findings, not live Snowflake test results. The
links follow development branches; check them again before changing
the backend.

[Posit's skiPatrol](https://github.com/posit-dev/skiPatrol) serves Snowflake ML
workflows through Snowpark. Assess it separately if the package adds model
registry or inference support.
