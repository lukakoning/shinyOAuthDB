# Snowflake: why skiLift is deferred

The current backend uses DBI and odbc with the user's OAuth token.
skiLift is promising because its SQL API could remove the need for an ODBC
driver, but its authentication interface needs changes before we can use it.

Source review on 1 November 2026 found:

- An explicit `token` was treated as a programmatic access token, including
  with `authenticator = "oauth"`. See [authentication resolution](https://github.com/posit-dev/skiLift/blob/main/R/auth.R).
- Refresh could read ambient Workspace credentials. A visitor's connection
  must keep using that visitor's authorization.
  See [token refresh](https://github.com/posit-dev/skiLift/blob/main/R/api.R).
- The public constructor accepted a token string but no external token
  callback. See the [constructor](https://github.com/posit-dev/skiLift/blob/main/R/driver.R).

Reconsider skiLift when it accepts an external OAuth token with the correct
token type, keeps that identity through refresh, and offers a supported way
to obtain renewed tokens or rebuild its connection. Test those behaviors
against Snowflake before adding a backend. Its
[transaction support](https://github.com/posit-dev/skiLift/blob/main/R/transactions.R)
also differs from ODBC and would need documenting.

These findings describe the inspected source, not a live Snowflake test.
The links follow development branches; recheck them when revisiting the decision.

[Posit's skiPatrol](https://github.com/posit-dev/skiPatrol) serves Snowflake ML
workflows through Snowpark. Consider it separately if the package gains a
model-registry, feature-store, or inference use case.
