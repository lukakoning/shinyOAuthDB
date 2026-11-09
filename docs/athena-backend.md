# Amazon Athena backend decision

Research and implementation: 9 November 2026.

`oauth_db_athena()` uses the public Amazon Athena ODBC 2.x `JWT_TIP`
credentials provider through `odbc::odbc()` and DBI. shinyOAuth retains
browser sign-in and refresh; the driver performs the AWS token exchange,
query submission and result retrieval. See the [source guide](../vignettes/athena.Rmd).

## Driver choice

AWS documents [JWT trusted identity propagation](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver-jwt-tip.html)
as a connection mode accepting an external provider's JWT. It preserves
the Identity Center user context for configured AWS data permissions.
The helper deliberately supports this mode rather than offering an
ordinary assumed-role JWT mode with different authorization semantics.

The [setup guide](https://docs.aws.amazon.com/athena/latest/ug/using-trusted-identity-propagation-setup.html)
describes the federated application role, access role, customer managed
Identity Center application and workgroup tags. The application role is
obtained through `AssumeRoleWithWebIdentity`; no host AWS credential chain
is needed for that exchange. Missing optional ARNs use the driver's tag
discovery under that role, not credentials discovered by the R helper.

The R SDK alternative, for example [noctua](https://dyfanjones.github.io/noctua/reference/dbConnect-AthenaDriver-method.html),
accepts AWS keys, profiles and SDK credential sources. Using it here would
require implementing and maintaining the Identity Center exchange and
its credential lifetime separately. Direct REST has the same requirement,
plus SigV4 signing and query/result handling. AWS JDBC also supports TIP,
but adds a JVM and another R driver layer. ODBC supplies an existing DBI
interface with the required token entry point and no new R dependency.

Use Amazon Athena ODBC 2.5.0.0 or later. The
[download page](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver.html)
lists Windows, macOS and Linux x86_64 drivers. Earlier ODBC versions added
TIP in 2.0.5.0; this implementation documents the current driver and its
cache controls rather than claiming validation of every 2.x release.

## Configuration and session behavior

The workgroup ARN supplies the region and workgroup name. The helper
validates role/application ARN kinds and partitions before binding an
authorization. It allows result and timeout options, with native names
canonicalized after duplicate checks. DSNs, credential sources, endpoint
overrides, logging and alternate TLS settings can't enter through `...`.
Shared ODBC validation prevents connection-string injection.

Each connection receives an explicit visitor token and a new random STS
role session name. File credential caching is disabled. AWS's
[advanced options](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver-advanced-options.html)
also describe a process-level workgroup connection-check cache; this is
disabled, as are query result reuse and native logging. TLS certificate
verification stays enabled. These settings don't establish how every
internal vendor credential cache behaves with a live AWS integration. The
native fixture checks credential separation with synthetic exchanges;
configured AWS acceptance remains necessary.

A digest of the current token controls connection reuse. Renewal replaces
the native connection on its next use without invalidating completed
reactive queries. Account replacement, scope loss, sign-out and session
end use the existing cleanup lifecycle. No SQL retry is added.

Tokens with a `jti` can have a single-use exchange restriction. A broken
connection may need a new visitor token before it can reconnect. We keep
the shared file cache disabled and document this limitation rather than
reusing another connection's credentials. Native connections retained
outside the accessor, submitted AWS jobs and saved S3 results have their
own lifetime; local sign-out isn't a guarantee of server-side cancellation.

## Acceptance boundary

Unit tests exercise the real Shiny authorization/session layer, mocked
native ODBC calls and real disposable SQLite handles for lifecycle checks.
The source guide is included in the complete-app signed-out checks, and
the native missing-driver diagnostic test includes Athena.

The [Linux transport fixture](../integration/athena-odbc/README.md) exercises
Amazon Athena ODBC 2.5.0.0 through R odbc against local TLS services,
with external networking disabled. Two synthetic visitor tokens reached
`AssumeRoleWithWebIdentity` under distinct role session names, without
using unrelated host AWS keys. The fixture's rejection reached R without
a retry or token-bearing error trace. A mismatched TLS hostname failed
before the fixture received an HTTP request.

A second phase supplies synthetic STS, Identity Center and Athena responses
so the real driver can open connections and execute SQL through DBI. Alice,
Bob and a renewed Alice token produced separate credential exchanges and
correct results across six interleaved queries, while all three connections
remained open. Every connection checked its own workgroup, and no file cache
appeared. This exercises native protocol and credential handling; the
emulator doesn't validate JWT signatures, AWS policy or Lake Formation
permissions, and its credentials can't access AWS.

On Windows 11 with R 4.5.1, the isolated source suite passed 7,912 assertions
across 466 scenarios with no failures, warnings or skips. `R CMD check
--no-manual` completed with zero errors, warnings or notes, and pkgdown built
the new article and reference page. The native fixture passed with Linux
R 4.5.1 and odbc 1.7.2. Changed R files pass Air and Jarl; full-repository
Jarl separately reports two existing implicit assignments in the asynchronous
getting-started tests.

Live acceptance requires a configured AWS integration and two users with
different grants. Check the propagated principal in CloudTrail, allowed
and denied data access, result-location access, refresh and reconnect,
account switching, independent simultaneous sessions and behavior with
unrelated host AWS credentials present. Verify that no file cache appears
and that the driver doesn't share derived credentials between users.
Check that users can't retrieve another user's saved query results.
No live AWS acceptance result is claimed by these fixtures.
