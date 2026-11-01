# Snowflake backend decision

Reviewed 1 November 2026. The supported Snowflake backend remains DBI + odbc
with an explicitly supplied OAuth access token. skiLift and skiPatrol are not
dependencies or supported backends of shinyOAuthDB.

## Posit's packages

Posit [announced skiLift and skiPatrol on 15 September 2026](https://posit.co/blog/r-meet-snowflake-introducing-posits-skilift-and-skipatrol-packages).
They continue the RSnowflake and snowflakeR projects respectively.

| Package | Purpose | Decision |
| --- | --- | --- |
| [skiLift](https://github.com/posit-dev/skiLift) | DBI/dbplyr through the Snowflake SQL API, with optional ADBC acceleration | Reconsider after its public authentication interface supports externally managed user credentials |
| [skiPatrol](https://github.com/posit-dev/skiPatrol) | Snowflake ML features through Python/Snowpark | Defer until there is a concrete model registry, feature store, or inference use case |
| [snowflakeauth](https://github.com/posit-dev/snowflakeauth) | Authentication and connection-profile helpers | Leave native clients free to use it; shinyOAuth continues to own this bridge's authorization and refresh |

## Why skiLift is deferred

The SQL API route could simplify Shiny deployment because ordinary queries do
not require an ODBC driver, JVM, or Python runtime. However, inspection of the
current `main` branch found these integration obstacles:

1. An explicit `token` is classified as `PROGRAMMATIC_ACCESS_TOKEN`, including
   when `authenticator = "oauth"`. OAuth tokens from shinyOAuth must retain
   OAuth semantics. See [authentication resolution](https://github.com/posit-dev/skiLift/blob/main/R/auth.R)
   and its explicit-token regression in [test-auth.R](https://github.com/posit-dev/skiLift/blob/main/tests/testthat/test-auth.R).
2. The refresh path for token connections can read ambient Workspace
   credentials. A delegated Shiny connection must stay bound to its selected
   authorization and must not adopt the hosting environment's identity. See
   [token refresh](https://github.com/posit-dev/skiLift/blob/main/R/api.R).
3. The inspected public constructor accepts a token string but has no external
   token-provider callback. Rebuilding a stateless handle when credentials
   rotate is possible once the preceding issues are resolved; a callback would
   also allow renewal during polling and multi-request operations. See the
   [constructor](https://github.com/posit-dev/skiLift/blob/main/R/driver.R).

Its DBI interface also has different capabilities from ODBC: the current
[transaction methods](https://github.com/posit-dev/skiLift/blob/main/R/transactions.R)
reject transactions, and statements and write batches commit independently.
Future support must describe these native semantics explicitly.

These are source-review findings, not a live Snowflake validation. The links
track development and may change; recheck them before revisiting this decision.

## Conditions for future support

- A public way to supply an external OAuth access token with the correct
  token type, without patching private slots.
- Explicit external credentials must never fall back to environment, profile,
  or Workspace credentials when unavailable or expired.
- Refresh must use a public callback into shinyOAuth, or an adapter must obtain
  a current credential and rebuild the native handle before each operation as
  needed. Already-running operations retain the native client's limitations.
- Verify per-user identity, role, refresh, authorization replacement, logout,
  and optional ADBC transport against a live integration.

Do not work around these requirements with process-wide token environment
variables or generated credential profiles. Keep skiLift optional if it becomes
supported; return its native DBI connection and leave queries to the package.

skiPatrol's public `sfr_connect(session = ...)` could accept an explicitly
created user-bound Snowpark session in a later adapter. That would require
separate Python-session ownership, refresh, and cleanup work. It is outside the
current SQL integration scope.
