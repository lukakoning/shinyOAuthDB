# Oracle backend decision

Investigated on 8 November 2026. The first Oracle adapter uses the vendor's
ODBC driver with Microsoft Entra OAuth access tokens and returns an odbc
DBI connection. Both self-hosted and hosted databases are in scope when
their edition, version and configuration support Entra integration.

## Driver and authentication

Oracle's [ODBC guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/odbcd/using-oracle-database-odbc-driver.html)
documents passing an externally acquired Entra access token through a file
selected by `TOKEN_LOCATION` with `TOKEN_AUTH=OAUTH`. The adapter uses
this route with the package's existing optional odbc dependency. It adds
neither an Oracle client binding nor a Java runtime dependency.

The database resource URI is deployment-specific. The existing
`oauth_db_microsoft_client()` accepts a custom named token target, so
there is no hard-coded Oracle resource in the Microsoft service profiles.
The [Oracle setup example](https://docs.oracle.com/en/learn/ocidb-auth-msentraid/)
uses the delegated `session:scope:connect` permission. The server
registration, access-token claims and global database user/role mappings
must be configured by the administrator.

Oracle's [client support table](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/supported-client-drivers-entra-ad-connections.html)
includes the 19c thick client from 19.16 and current supported releases,
excluding the 21c thick client. Driver names do not reliably encode their
version, so the helper also checks the authentication method after opening
a connection and rejects a session unless it reports `TOKEN_GLOBAL`.
Oracle documents that result in its
[Entra authentication validation](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/configuring-microsoft-entra-id-proxy-authentication.html).

OCI IAM is a separate integration. Its token-file path uses a private key
to prove possession. An OAuth bearer string alone does not implement it.
ROracle and JDBC remain possible future transports; neither is required
for this ODBC implementation.

## Per-session isolation

Each native connection gets a separate token file and an inline Oracle
Net descriptor passed as `DBQ`. The
[Oracle Net reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/local-naming-parameters-in-tns-ora-file.html)
documents connection-string precedence for token settings. The helper
does not edit `tnsnames.ora`, `sqlnet.ora`, or `TNS_ADMIN`.

The descriptor fixes TCPS, token authentication and certificate matching.
Both `SSL_` and `TLS_` spellings carry identical matching settings for
client-version compatibility. `AUTHENTICATION_SERVICE=NONE` disables
network authentication alternatives; the subsequent `TOKEN_GLOBAL` check
guards against returning a session authenticated another way.

The token directory is created with mode 0700 and the file uses mode 0600
on Unix. Windows inherits its temporary-directory ACLs, as with the
existing StarRocks adapter. The token file and directory are removed on
success, error and interrupt. Oracle ODBC's documented `FEN=F` disables
automatic failover because the token path no longer exists after opening.
The caller reconnects through the reactive helper to obtain a current
token. Ordinary token renewal preserves an established SQL session.

The adapter accepts an explicit host and service name instead of an
arbitrary connect descriptor, DSN or alias. Additional arguments have a
small allowlist of result settings, timeout, fetch-buffer size and access
mode. Callers cannot replace token files, credentials, destinations or
TLS settings through native options.

## Validation boundary

Tests exercise the real R odbc connection-string builder up to its native
connection boundary. Mocked Oracle authentication responses and real
SQLite DBI connections cover rejection of alternate authentication,
failure and interrupt cleanup, current tokens on reconnect, account
changes, permission loss, sign-out and session termination. The source
guide's complete Shiny app is included in the guide checks.

No Oracle driver or Entra-enabled Oracle database was available for this
implementation. Before recording live compatibility, check the principal
and authentication method with two distinct visitors, verify their
different grants, token expiry and reconnect behavior, and confirm TLS
validation against the target client and database versions.
