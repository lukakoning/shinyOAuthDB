# Additional OAuth backends

Investigated 1 November 2026. BigQuery now uses a direct REST implementation.
The Redshift and Trino interfaces below remain proposals.

Trino is the best next addition technically. Redshift has a suitable ODBC
interface but needs a configured AWS deployment for testing. BigQuery remains
valuable, although its R client needs a different integration design.

| Platform | Preferred route | Assessment |
| --- | --- | --- |
| Trino / Starburst Enterprise | RTrino DBI connection with an authentication callback | Proceed to a backend prototype |
| Redshift | DBI + AWS ODBC driver, supplied user token | Proceed with a live Identity Center fixture |
| Dremio Enterprise | DBI + Flight SQL ODBC; consider adbi/ADBC for token exchange | Start with a configured external token provider |
| BigQuery | Direct REST client with per-user tokens | Implemented as `oauth_db_bigquery_api()` |

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

Implemented with `oauth_db_bigquery_api()` and
`oauth_db_bigquery_client()`. Queries, polling, and pagination use a token
callback tied to the selected authorization. The client returns data frames,
preserves INT64 and decimal precision, and supports named query parameters.
See the [BigQuery guide](../vignettes/platform-apis.Rmd#google-bigquery).

The direct REST approach avoids bigrquery's package-global authentication.
The investigation with bigrquery 1.6.2 confirmed that two DBI connections used
the most recently configured package token, even when created with different
`token` arguments. Its [constructor](https://github.com/r-dbi/bigrquery/blob/main/R/dbi-driver.R)
does not bind authentication to the connection.

Google's [query](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query)
and [result](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/getQueryResults)
APIs define the transport. A unique request ID protects a submission's single
401 refresh retry; other failures do not resubmit SQL. Local timeouts and
sign-out stop fetching, while an already submitted Google job can continue.

## Scope of the evidence

The R probes ran on Windows with R 4.5.1, shinyOAuth 0.7.0, bigrquery 1.6.2,
and RTrino 0.1.0. Additional packages went into a temporary research library.
The probes used fixture credentials and mocked HTTP; no cloud resources,
browser OAuth flows, or production credentials were used.

The next implementation should keep native DBI objects and ordinary queries.
New R6 clients are useful where a connection cannot carry its own credentials,
as with the potential BigQuery API client. Source links on development branches
may change; the installed R package versions above identify the runtime probes.
