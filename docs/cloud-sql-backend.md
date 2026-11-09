# Cloud SQL backend decision

Research and implementation: 9 November 2026.

Cloud SQL for PostgreSQL accepts Google OAuth access tokens as passwords
with manual IAM database authentication. Use that interface with RPostgres,
keeping shinyOAuth responsible for browser sign-in and token renewal.
The Google client requests identity scopes and
`https://www.googleapis.com/auth/sqlservice.login`. Google's
[connector implementation](https://github.com/GoogleCloudPlatform/cloud-sql-python-connector/blob/main/google/cloud/sql/connector/refresh_utils.py)
uses that login scope for its IAM credential refresh. The package doesn't
request Cloud SQL administration or load Application Default Credentials.

## Connection path

The helper returns native DBI connections through the existing session
lifecycle. A username function selects the IAM database principal for the
current authorization. A digest of the access token controls connection
reuse: the next accessor call after renewal opens with current credentials,
without invalidating completed reactive queries just because token bytes
changed. Permissions, account replacement and session ownership retain the
shared lifecycle checks.

PostgreSQL requires libpq 16 or later, `require_auth=password`,
`sslmode=verify-full`, and disabled GSS encryption. `hostaddr` can route to
an IP while `host` remains the certificate identity. Ambient connection
service files are rejected. Extra driver options are limited to the
documented result, application name, timeout and keepalive settings.

Direct connections require network reachability, IAM account provisioning,
Cloud SQL Instance User and separate SQL grants. Verified hostnames require
an appropriate server CA configuration and DNS setup. The helper doesn't
weaken verification for an instance certificate without a matching name.

Automatic IAM authentication through a shared Cloud SQL Auth Proxy uses
the account that starts it. It isn't the default because it would replace
visitor identities with that account. No proxy management or infrastructure
provisioning is included.

## MySQL investigation

Cloud SQL for MySQL also documents manual IAM login, using the access token
as a password through `mysql_clear_password`. A prototype used MySQL
Connector/ODBC 9.5.0 with verified TLS and disabled automatic reconnection.
Short synthetic credentials authenticated, queries returned separate user
results, and credential replacement opened a new connection.

The native Linux driver crashed on both 2048-byte and 12005-byte synthetic
passwords against a local TLS protocol fixture. Google documents a standard
OAuth [access-token limit of 2048 bytes](https://developers.google.com/identity/protocols/oauth2#size),
so rejecting only unusually large tokens doesn't establish a reliable path.
The prototype isn't exported or advertised as supported. Investigate a
driver version that passes token-length and failure tests, or an R client
exposing cleartext authentication with enforced TLS and hostname verification.
No Google or Cloud SQL MySQL deployment was tested. Cloud SQL for SQL Server
doesn't provide this IAM database login path.

## Sources and validation

- [PostgreSQL IAM login](https://docs.cloud.google.com/sql/docs/postgres/iam-logins)
- [MySQL IAM login](https://docs.cloud.google.com/sql/docs/mysql/iam-logins)
- [PostgreSQL server certificates and DNS](https://docs.cloud.google.com/sql/docs/postgres/configure-ssl-instance)
- [MySQL ODBC connection parameters](https://dev.mysql.com/doc/connector-odbc/en/connector-odbc-configuration-connection-parameters.html)
- [Google Web OAuth clients](https://developers.google.com/identity/protocols/oauth2/web-server)

Unit tests cover native driver arguments, scope enforcement, configuration
overrides, token replacement, account isolation, username changes and
connection cleanup. The source guide's app is constructed and checked
while signed out. `tools/check-cloud-sql.R` reuses the local PostgreSQL
password fixture to check native TLS, SQL row policies, write denial,
identity mismatch, renewed credentials and refusal of trust authentication.
These synthetic credentials don't establish Google IAM compatibility.
Live Cloud SQL sign-in, IAM mapping and Google certificate configuration
still require an existing instance and Google OAuth registration.
