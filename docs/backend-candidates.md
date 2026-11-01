# Additional OAuth backends

Investigated 1 November 2026. This is a feasibility assessment; the proposed
helpers below are not implemented.

Trino is the best next addition technically. Redshift has a suitable ODBC
interface but needs a configured AWS deployment for testing. BigQuery remains
valuable, although its R client needs a different integration design.

| Platform | Preferred route | Assessment |
| --- | --- | --- |
| Trino / Starburst Enterprise | RTrino DBI connection with an authentication callback | Proceed to a backend prototype |
| Redshift | DBI + AWS ODBC driver, supplied user token | Proceed with a live Identity Center fixture |
| Dremio Enterprise | DBI + Flight SQL ODBC; consider adbi/ADBC for token exchange | Start with a configured external token provider |
| BigQuery | bigrquery API client, if calls can use a bounded authentication scope | Investigate further before promising DBI support |

## Trino and Starburst

[RTrino 0.1.0](https://cran.r-project.org/package=RTrino), published on
15 October 2026, is a better starting point than RPresto. Its `dbConnect()`
accepts an `auth` function that receives an httr2 request. The
[request builder](https://github.com/AngelCasasbl/RTrino/blob/3421e6f508a83f77f6e28d12a70048cd838d8b02/R/utils.R)
calls it for connection checks and query requests, including pagination.
This gives shinyOAuthDB a public place to obtain a current token.

A local probe used the released R package, real DBI calls, and shinyOAuth
fixture authorizations, with HTTP responses mocked. A token rotated between
the query submission and a result page; the page used the new token and the
same DBI connection remained usable. Changing accounts closed the old
connection. Retained callbacks failed after replacement, logout, and session
closure.

A future helper could look like:

```r
con <- oauth_db_trino(
  auth$connection,
  host = "https://trino.example.org",
  port = 443,
  catalog = "lakehouse",
  schema = "reporting",
  user = "mapped-database-user"
)
```

It would return the usual connection function. Reuse the existing
grant-bound callback internally so an old connection cannot adopt a newly
selected account. RTrino's `trino_auth_oauth2()` uses client credentials;
the adapter should supply the visitor's token through `auth` instead.
See the [authentication helpers](https://github.com/AngelCasasbl/RTrino/blob/3421e6f508a83f77f6e28d12a70048cd838d8b02/R/auth.R).

The username needs an explicit mapping to the selected authorization.
RTrino's operating-system username default is unsuitable for this purpose.
Before release, test against a real cluster, including principal mapping,
permission denial, cancellation, and token expiry. Per-request acquisition
does not guarantee renewal within an HTTP retry or replay after a 401.

For [Starburst Enterprise](https://docs.starburst.io/latest/security/oauth2.html),
the same transport is a candidate once the cluster trusts the IdP and maps
the user. **Galaxy needs its own sign-in configuration**:
it supports custom public and confidential OAuth clients. Confidential
clients require HTTPS redirect URIs. Its OAuth endpoints and permissions
must be tested separately; compatibility with Trino's SQL protocol does not
establish Galaxy sign-in support.
See [Galaxy client registration](https://docs.starburst.io/starburst-galaxy/security-and-compliance/manage-galaxy-access/setup-oauth-clients.html).

## Amazon Redshift

AWS documents an external-token route specifically for applications that own
their sign-in flow: `plugin_name = "IdpTokenAuthPlugin"`, with `token` and
`token_type`. `EXT_JWT` denotes a token from an integrated external IdP;
`ACCESS_TOKEN` denotes an IAM Identity Center access token.
This requires the deployment's Identity Center integration and user mapping.
See [AWS's integration guide](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-oauth.html).

Proposed interface:

```r
con <- oauth_db_redshift(
  auth$connection,
  server = "cluster.example.eu-west-1.redshift.amazonaws.com",
  database = "reporting",
  driver = "your installed Redshift ODBC driver",
  token_type = "EXT_JWT"
)
```

The existing generic connector can already pass a token to DBI/odbc using
`odbc::odbc()`. The convenience [`odbc::redshift()`](https://odbc.r-dbi.org/reference/redshift.html)
method discovers IAM credentials, which is unsuitable for this supplied-token
path. A dedicated helper would set the native authentication options, enforce
TLS, and close the connection on authorization changes. The client's IdP and token
audience depend on the deployment, so a universal Redshift sign-in preset
would be misleading.

The reviewed AWS ODBC 2.3.0
[plugin source](https://github.com/aws/amazon-redshift-odbc-driver/blob/868e9b0d035f5e219890c2de424b9d29d130f300/src/odbc/rsodbc/iam/plugins/IdpTokenAuthPlugin.cpp)
uses the supplied token when both token fields are present. Missing both
allows AWS default-credential discovery; partial pairs and mixed IAM/token
credentials fail. The helper should require the pair and prevent profiles,
DSNs, or other credential options from selecting a different identity.

Set `SSLMode = "verify-full"` explicitly. The
[2.3.0 changelog](https://github.com/aws/amazon-redshift-odbc-driver/blob/868e9b0d035f5e219890c2de424b9d29d130f300/CHANGELOG.md)
describes a compatibility exception for the driver's implicit default.

Start with the documented external-token flow. Identity-enhanced IAM sessions
and `SUBJECT_TOKEN` involve another acquisition path; they should be separate
work. Live tests must establish the actual database principal, A/B grants,
expiry/reconnection, and isolation from ambient AWS credentials.
No AWS driver or remote connection was tested in this investigation.

## Dremio

The [Enterprise authentication guide](https://docs.dremio.com/current/security/authentication/)
supports both direct external JWTs and exchanging an external JWT for a
Dremio token. The [Flight SQL ODBC guide](https://docs.dremio.com/current/client-applications/drivers/arrow-flight-sql-odbc-driver/)
explicitly accepts an OAuth access token through `TOKEN`. A configured
Enterprise deployment is therefore a reasonable first target.

Proposed interface for direct token use:

```r
con <- oauth_db_dremio(
  auth$connection,
  host = "dremio.example.org",
  port = 32010,
  driver = "your installed Flight SQL ODBC driver"
)
```

Use the deployment's external IdP for sign-in. Dremio's `/oauth/token`
endpoint alone does not provide a browser authorization-code flow.

For [JWT exchange](https://docs.dremio.com/current/reference/api/oauth-token/#exchange-an-external-jwt),
Dremio accepts an RFC 8693 request. The resulting token lasts no longer than
the external JWT, capped at one hour. Choosing a shinyOAuth token target
does not perform this exchange.

Prefer an existing driver's exchange support over adding another OAuth token
store here. The [ADBC Flight SQL driver](https://arrow.apache.org/adbc/current/driver/flight_sql.html#oauth-2-0-options)
exposes token-exchange options, including the subject token and token endpoint.
That makes `adbi` an alternative worth testing, with connections rebuilt when
a stored subject token changes. Its R loading, exchange behavior, and query
lifetime still need verification.

Keep **Dremio Cloud** separate. Its
[authentication overview](https://docs.dremio.com/dremio-cloud/security/authentication/)
describes external JWT exchange, but its
[SQL driver page](https://docs.dremio.com/dremio-cloud/explore-analyze/client-apps/drivers/arrow-flight-sql-odbc/)
describes the token property as a PAT. Validate the exact Cloud driver and
edition before claiming delegated OAuth support. No live Dremio tests ran.

## Google BigQuery

**A bigrquery DBI connection currently does not own its authentication.**
In bigrquery 1.6.2, `dbConnect()` stores query settings, while requests obtain
the package's current token. The `token` argument in `dbConnect(..., token = x)`
is ignored. See the [connection constructor](https://github.com/r-dbi/bigrquery/blob/main/R/dbi-driver.R)
and [authentication state](https://github.com/r-dbi/bigrquery/blob/main/R/bq-auth.R).

A local probe created two connections with different fixture tokens, then
called `dbListTables()` through each with HTTP mocked. Both used user B after
`bq_auth(token = B)`. Switching the package token back to A changed subsequent
requests through the existing connection.

An API client is a possible narrower design:

```r
bigquery$call(
  bigrquery::bq_project_query,
  "billing-project",
  "SELECT * FROM reporting.Orders LIMIT 20"
)
```

A prototype using only public bigrquery functions temporarily installed a
token for one synchronous call and restored prior authentication on exit.
Sequential A/B/A metadata calls used the right token; success and errors both
restored the prior state, including an initially unauthenticated state.

This proves a possible mechanism, not a general session-safe adapter.
Before shipping it, define serialization/reentrancy rules, prevent DBI
connections or deferred work from escaping the scope, and test refresh and
the BigQuery Storage/Arrow download path. A per-connection or per-request
credential hook upstream would avoid the shared-state restriction.

Two driver alternatives also need separate treatment:

- The [Foundry Go driver](https://adbc-drivers.org/drivers/bigquery/#connection-options)
  documents ADC, credential JSON, and driver-managed user refresh. The reviewed
  interface does not provide the direct Google access-token callback needed
  for this bridge. The C# driver's
  [`adbc.bigquery.access_token` option](https://github.com/adbc-drivers/bigquery/blob/c371d617d5619b451f11faf33dec76bbd18d9389/csharp/src/AdbcDrivers.BigQuery/readme.md)
  belongs to its Entra federation path; it is not a drop-in Google OAuth token
  argument or an R callback.
- Progress DataDirect documents access-token-only authentication, making
  DBI/odbc a possible vendor-specific route. Its client settings, deployment
  requirements, and token expiry need a real-driver test.
  See its [driver guide, pages 50–51 and 76–77](https://progress-be-prod.zoominsoftware.io/bundle/datadirect-pdfs/raw/resource/enus/datadirect-google-bigquery-odbc-80.pdf).

Use shinyOAuth's existing Google provider for any future Google sign-in setup.
Billing project and dataset remain query settings, rather than Microsoft-style
OAuth token targets. Do not publish a general `oauth_db_bigquery()` DBI helper
based on package-global `bq_auth()`.

## Scope of the evidence

The R probes ran on Windows with R 4.5.1, shinyOAuth 0.7.0, bigrquery 1.6.2,
and RTrino 0.1.0. Additional packages went into a temporary research library.
The probes used fixture credentials and mocked HTTP; no cloud resources,
browser OAuth flows, or production credentials were used.

The next implementation should keep native DBI objects and ordinary queries.
New R6 clients are useful where a connection cannot carry its own credentials,
as with the potential BigQuery API client. Source links on development branches
may change; the installed R package versions above identify the runtime probes.
