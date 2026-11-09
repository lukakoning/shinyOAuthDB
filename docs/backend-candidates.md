# Backend decisions

Research notes from 1 November 2026. BigQuery, Redshift, and Trino are
implemented; Dremio now uses ADBC Flight SQL. For app examples, start with the
[source guides](../vignettes/getting-started.Rmd).

Oracle was added after this investigation; see the
[Oracle backend decision](oracle-backend.md) for its OAuth/ODBC and ORDS scope and
validation limits.

SAP HANA and HANA Cloud now use SAP HANA ODBC with visitor JWT access
tokens; see the [HANA backend decision](hana-backend.md) for the database
configuration and validation boundary.

| Platform | Implementation |
| --- | --- |
| BigQuery | `oauth_db_bigquery_api()`: direct REST queries |
| Redshift | `oauth_db_redshift()`: user tokens through the AWS ODBC driver |
| Trino / Starburst Enterprise | `oauth_db_trino()`: RTrino with an authentication callback |
| Dremio | `oauth_db_dremio()`: bearer access tokens through ADBC Flight SQL and adbi |

The probes used fixture credentials and mocked HTTP on Windows with R 4.5.1,
shinyOAuth 0.7.0, bigrquery 1.6.2, and RTrino 0.1.0. Extra packages were
installed in a temporary library. No browser sign-in or live cloud queries
ran during this investigation.

## BigQuery: use the REST API

bigrquery 1.6.2 uses package-wide authentication. In a local probe, two DBI
connections used the most recently configured package token even when they
were created with different `token` arguments. Its
[connection constructor](https://github.com/r-dbi/bigrquery/blob/main/R/dbi-driver.R)
doesn't keep separate credentials for each connection.

The BigQuery client therefore calls Google's
[query](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query)
and [result](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/getQueryResults)
APIs directly. Each operation keeps the authorization it started with and
gets a current token for polling and result pages. Queries return data
frames, preserve INT64 and decimal precision, and accept named parameters.

A unique request ID protects the single 401 refresh retry. Other failures
don't resubmit SQL. A timeout or sign-out stops fetching results, while a
submitted Google job may continue. See the [BigQuery guide](../vignettes/bigquery.Rmd).

## Redshift: supply the user token to ODBC

AWS's [Identity Center integration](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-oauth.html)
accepts tokens through `IdpTokenAuthPlugin`. The `EXT_JWT` mode uses a JWT
from a trusted external provider; `ACCESS_TOKEN` uses an IAM Identity Center
access token. The deployment supplies the issuer and user mapping, so the
package has no universal Redshift sign-in preset.

The helper uses `odbc::odbc()` with explicit `token` and `token_type`
arguments. The convenience [`odbc::redshift()`](https://odbc.r-dbi.org/reference/redshift.html)
function discovers IAM credentials.

The reviewed AWS ODBC 2.3.0
[plugin](https://github.com/aws/amazon-redshift-odbc-driver/blob/868e9b0d035f5e219890c2de424b9d29d130f300/src/odbc/rsodbc/iam/plugins/IdpTokenAuthPlugin.cpp)
uses the supplied token when both token fields are present. If both are
missing, it can discover default AWS credentials. The helper always supplies
the pair and rejects profiles, DSNs, and competing credential options.

It also sets `SSLMode = "verify-full"` explicitly because the
[2.3.0 changelog](https://github.com/aws/amazon-redshift-odbc-driver/blob/868e9b0d035f5e219890c2de424b9d29d130f300/CHANGELOG.md)
documents a compatibility exception for the implicit default.

The adapter tests cover arguments and connection lifetime. Live tests still
need to check the database principal, separate A/B access, reconnection, and
isolation from the host's AWS credentials. No AWS driver connection was
tested in this investigation. Identity-enhanced IAM credentials and
`SUBJECT_TOKEN` require separate work.

## Trino: use RTrino's authentication callback

RTrino 0.1.0 accepts an `auth` function in `dbConnect()`. Its
[request builder](https://github.com/AngelCasasbl/RTrino/blob/3421e6f508a83f77f6e28d12a70048cd838d8b02/R/utils.R)
calls this function for connection checks, query submission, and result pages.
The helper uses it to obtain a current user token.

Tests with the released package and mocked HTTP confirmed that a result
page could use a renewed token on the same DBI connection. Switching
accounts closed the old connection. Retained callbacks failed after account
replacement, sign-out, and session end.

The `user` argument must match the cluster's principal mapping. The helper
accepts a reactive function and replaces the connection when the username
changes. RTrino's
[`trino_auth_oauth2()`](https://github.com/AngelCasasbl/RTrino/blob/3421e6f508a83f77f6e28d12a70048cd838d8b02/R/auth.R)
uses client credentials; this helper supplies the visitor's token.

Live validation still needs to cover principal mapping, permission denial,
cancellation, and expiry. Obtaining a token per request doesn't guarantee
renewal during an HTTP retry or replay after a 401.

[Starburst Enterprise](https://docs.starburst.io/latest/security/oauth2.html)
needs the corresponding issuer and user mapping. Galaxy requires its own
[OAuth registration](https://docs.starburst.io/starburst-galaxy/security-and-compliance/manage-galaxy-access/setup-oauth-clients.html);
its confidential clients require HTTPS redirects. SQL protocol compatibility
alone doesn't establish Galaxy sign-in support.

## Dremio: ADBC Flight SQL

The helper sends visitor access tokens directly to a TLS Flight SQL
endpoint through adbi. It reconnects after token changes and uses the
existing Shiny authorization and cleanup lifecycle. Browser sign-in and
renewal remain with shinyOAuth; Dremio token exchange is not performed.
See the [backend decision](dremio-backend.md) for the driver comparison,
Cloud edition boundary and validation limits, and the
[Dremio guide](../vignettes/dremio.Rmd) for a complete Shiny app.

## Salesforce CRM and Data Cloud

The Salesforce backend uses direct, session-bound HTTPS clients. CRM queries
use the REST Query/QueryAll resources, query locators and native object
discovery. Data Cloud (Data 360) uses Query Connect API on the Salesforce org
with the same user's Salesforce access token. It submits SQL once, polls the
query status and retrieves rows by offset.

Salesforce's [Query API overview](https://developer.salesforce.com/docs/data/data-cloud-query-guide/references/data-cloud-query-api-reference/c360a-api-queryservices-overview.html)
recommends Query Connect API for integrations and supersedes legacy Query
V1/V2. This avoids a second credential store for Direct API token exchange.
The documented [request/response example](https://developer.salesforce.com/docs/data/connectapi/guide/query-use-case.html)
supplies bound parameter descriptors, column types, completion status and
row counts. Returned query IDs can contain an encoded slash; request URL
construction must preserve it when adding query parameters.

New registrations should use External Client Apps. Enable
[JWT-based access tokens for named users](https://help.salesforce.com/s/articleView?id=sf.jwt_eca_configuration.htm&language=en_US&type=5):
shinyOAuth rejects legacy opaque Salesforce tokens containing `!`. The
helpers retain its existing credential validation rather than overriding it.
Signed ID-token validation and access-token format are separate concerns.

Contract tests cover current-token use on result pages, account changes,
scope requirements, sanitized errors, request deadlines, exact numeric
results and refusal to replay SQL submission. They use synthetic
authorizations and documented response shapes. Live acceptance still needs
an org registration, JWT access tokens, licenses and two users with different
CRM/Data Cloud permissions. See the [Salesforce guide](../vignettes/salesforce.Rmd).
