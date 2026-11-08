# Oracle backend decision

Investigated on 8 November 2026. Native SQL uses Oracle ODBC with a JWT
accepted by the database's configured OAuth provider. ORDS REST resources
use a separate HTTP client. Self-hosted and hosted deployments need the
server/client versions, provider trust and privileges required by their
chosen integration.

## Driver and authentication

Oracle's [ODBC guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/odbcd/using-oracle-database-odbc-driver.html)
documents passing an externally acquired Entra access token through a file
selected by `TOKEN_LOCATION` with `TOKEN_AUTH=OAUTH`. The adapter uses
this route with the package's existing optional odbc dependency. It adds
neither an Oracle client binding nor a Java runtime dependency.

The initial Entra-only investigation missed newer OCI IAM OAuth and
Keycloak integrations. Oracle's current
[direct-logon guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/configure-sql-client-end-user-direct-logon.html)
documents `TOKEN_AUTH=OAUTH` and token-file login for both. The transport
is therefore provider-neutral; it does not make an unconfigured issuer
acceptable to the database.

For Entra, the database resource URI is deployment-specific. The existing
`oauth_db_microsoft_client()` accepts a custom named token target, so
there is no hard-coded Oracle resource in the Microsoft service profiles.
The [Oracle setup example](https://docs.oracle.com/en/learn/ocidb-auth-msentraid/)
uses the delegated `session:scope:connect` permission. The server
registration, access-token claims and global database user/role mappings
must be configured by the administrator.

Oracle's Entra [client support table](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/supported-client-drivers-entra-ad-connections.html)
includes the 19c thick client from 19.16 and current supported releases,
excluding the 21c thick client. Driver names do not reliably encode their
version. In the default global-schema model the helper requires the
`TOKEN_GLOBAL` result documented in Oracle's
[Entra authentication validation](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/configuring-microsoft-entra-id-proxy-authentication.html).

OCI IAM Identity Domains OAuth bearer tokens are distinct from the older
IAM proof-of-possession token mechanism. The former uses `TOKEN_AUTH=OAUTH`;
the latter uses `TOKEN_AUTH=OCI_TOKEN` and a private key and is not
implemented by this bearer-token adapter. The
[OAuth configuration parameter](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/IDENTITY_PROVIDER_OAUTH_CONFIG.html)
is documented from Oracle 26ai RU 23.26.2.

Oracle's current [IAM configuration guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/configure-database-iam-integration.html)
also documents `IDENTITY_PROVIDER_TYPE=OAUTH2`, initially for Keycloak, with
issuer, JWKS, audience and identity/role claim mappings. The configurable
provider is not supported on Autonomous Database. The helper does not
configure these administrative settings or claim universal OIDC support.

ROracle and JDBC remain possible future transports; neither is required
for this ODBC implementation.

## End-user authorization verification

`authorization_model = "end_user"` explicitly selects Oracle Deep Data
Security direct logon. It requires jsonlite in addition to odbc. The helper
reads issuer, subject and audience from Oracle's immutable, system-managed
`ORA_END_USER_CONTEXT.USER.TOKEN` and compares them with the submitted JWT.
Oracle documents this context in its
[SQL reference](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/ora_end_user_context.html)
and [context guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/default-and-custom-contexts.html).

Local decoding supplies the expected identity; it does not authenticate the
JWT. The database validates the signature and creates the token context.
The verification query constructs JSON containing only `iss`, `sub` and
`aud`, avoiding unrelated token claims. Missing, malformed or mismatched
context closes the connection. The helper never falls back to accepting
global-schema privileges: Oracle documents that a global-user mapping can
[take precedence over Deep Data Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/end-user-security-context-issues.html).

End-user connections are replaced on access when the token changes, using
a hash as the connection reuse key. This propagates renewed identity and
role claims without making completed reactive queries depend on token
rotation. Global-schema connections retain their existing reuse behavior.
All operation scope names are now checked literally; Microsoft's
`/.default` consent convention is confined to the client configuration.

## Per-session isolation

Each native connection gets a separate token file and an inline Oracle
Net descriptor passed as `DBQ`. The
[Oracle Net reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/netrf/local-naming-parameters-in-tns-ora-file.html)
documents connection-string precedence for token settings. The helper
does not edit `tnsnames.ora`, `sqlnet.ora`, or `TNS_ADMIN`.

The descriptor fixes TCPS, token authentication and certificate matching.
Both `SSL_` and `TLS_` spellings carry identical matching settings for
client-version compatibility. `AUTHENTICATION_SERVICE=NONE` disables
network authentication alternatives; the selected authorization-model check
guards against returning a session with unintended privileges.

The token directory is created with mode 0700 and the file uses mode 0600
on Unix. Windows inherits its temporary-directory ACLs, as with the
existing StarRocks adapter. The token file and directory are removed on
success, error and interrupt. Oracle ODBC's documented `FEN=F` disables
automatic failover because the token path no longer exists after opening.
The caller reconnects through the reactive helper to obtain a current
token. Global-schema sessions survive ordinary token renewal; end-user
sessions reopen on access after token rotation.

The adapter accepts an explicit host and service name instead of an
arbitrary connect descriptor, DSN or alias. Additional arguments have a
small allowlist of result settings, timeout, fetch-buffer size and access
mode. Callers cannot replace token files, credentials, destinations or
TLS settings through native options.

## ORDS resources

`oauth_db_oracle_ords_api()` sends a visitor's current bearer token to the
configured HTTPS schema URL. It reuses the package's authorization pinning,
safe-read refresh retry, timeout handling and sanitized HTTP errors. It
does not follow redirects, server-provided links or pagination links.
`select()` reads a native AutoREST page; `request()` calls JSON handlers
with explicit relative paths and HTTP methods. Writes are not replayed.

ORDS [JWT profiles](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.3/orddg/developing-REST-applications.html)
can validate tokens from OCI IAM, Keycloak, Auth0 and Okta when issuer,
audience, signatures and scope/role mappings meet the configured profile.
Its resource privileges and `:current_user` identity do not automatically
map to distinct database schemas or SQL roles. Handlers must enforce the
intended data policy. The client returns native JSON, not a DBI connection
or an interpreter for application-specific success/error fields.

## Validation boundary

Tests exercise the real R odbc connection-string builder up to its native
connection boundary. Mocked Oracle authentication responses and real
SQLite DBI connections cover rejection of alternate authentication,
failure and interrupt cleanup, current tokens on reconnect, account
changes, permission loss, sign-out and session termination. The source
guides' complete Shiny apps are included in the guide checks. Additional
tests cover end-user context mismatch and token rotation, literal scopes,
ORDS paging metadata, renewal, writes, routing and late-response rejection.

No Oracle driver, configured Oracle database or ORDS service was available for this
implementation. Before recording live compatibility, check the principal
and authentication method with two distinct visitors, verify their
different grants, token expiry and reconnect behavior, and confirm TLS
validation against the target client and database versions.
