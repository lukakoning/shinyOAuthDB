# SQL Server, Fabric SQL, and PostgreSQL research

Research date: 2 October 2026. This report separates documented transport support, observed local implementation, and remaining integration validation. No live databases were contacted and no delegated-user connection was tested. Code fragments illustrate adapter boundaries, not an implemented public API.

## Conclusions for the package design

Use one Microsoft SQL token transport adapter with separate Azure SQL, Fabric SQL, and Entra-enabled SQL Server target profiles. Use a separate Azure PostgreSQL adapter because its transport is token-as-password and its token resource differs. Treat native PostgreSQL OAuth as an experimental adapter until an R driver exposes a safe externally supplied bearer-token interface. Ordinary PostgreSQL or older SQL Server deployments do not acquire OAuth support just because the Shiny application has an OAuth login.

The common abstraction should resolve a delegated credential for a configured resource and connect through an existing DBI backend. It should not assume one access token serves every target, equate OAuth consent with database grants, or turn a service connection into a user connection by adding a username to the query.

## Support matrix

| Target | External delegated-user token path | Reuse in R | Confidence and release placement |
| --- | --- | --- | --- |
| Azure SQL Database / Managed Instance | Entra SQL access token through the Microsoft ODBC pre-connect attribute | `DBI` + `odbc`, `attributes = list(azure_token = token)` | Documented interface; suitable initial adapter, live validation pending |
| Fabric Warehouse / Lakehouse SQL analytics endpoint | Same SQL token transport, with Fabric item/workspace permissions | `fabricQueryR::fabric_sql_connect()` initially; shared ODBC transport later if ownership is migrated | Existing local implementation plus official transport support; preserve Fabric-specific target rules |
| SQL Server 2022+ with Entra configured | Entra SQL access token after server-side setup | Same Microsoft ODBC adapter | Conditional support; cannot infer configuration from version alone |
| SQL Server without Entra support/configuration | No generic OAuth bearer path established | Existing DBI drivers can still support SQL/Windows authentication | Outside the delegated OAuth promise; optional explicit alternative integration only |
| Azure Database for PostgreSQL Flexible Server | Entra PostgreSQL token supplied as password | `DBI` + `RPostgres` | Straightforward documented transport; delegated role/mapping validation pending |
| PostgreSQL 18 native OAuth | OAUTHBEARER negotiation, custom server validator, libpq client flow/hook | `RPostgres` for DBI operations, but bearer injection hook is a gap | Experimental research; no claim of drop-in support |
| Ordinary PostgreSQL 17 and earlier | Native auth methods do not include OAuth | `RPostgres`, or an independently configured API/proxy/credential broker | Generic OAuth connection unavailable without extra infrastructure |

The table consolidates evidence explained and linked below. It describes the proposed scope, not a tested compatibility list.

## Microsoft SQL: identity and token boundaries

Azure SQL accepts tokens issued by Microsoft Entra, not arbitrary third-party identity providers. The server needs an Entra administrator and database principals mapped to the relevant users/groups. The access token authenticates the principal; database role membership and permissions still determine what SQL data is accessible. User, guest, group, application, and managed-identity configurations are supported, but application/managed-identity access represents that workload identity. [Microsoft: Azure SQL Entra authentication](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview?view=azuresql)

The delegated application registration needs the Azure SQL permission described by Microsoft as access to Azure SQL Database and Data Warehouse; an official end-user SSO example acquires a user token with `https://database.windows.net/.default`. Its particular example is Power BI, but the documented token acquisition requirement concerns Azure SQL. [Microsoft: generate an Azure SQL identity token](https://learn.microsoft.com/en-us/power-bi/developer/embedded/rls-sso#generate-an-identity-token)

Another official Microsoft tutorial explicitly adds the Azure SQL Database delegated permission `user_impersonation` to the application registration and requests `https://database.windows.net/user_impersonation` along with OIDC/refresh scopes. This is a documented named delegated scope for Azure SQL, not a generic permission suffix to append to every resource. [Microsoft: connect a web app to SQL as its user](https://learn.microsoft.com/en-us/azure/app-service/tutorial-connect-app-access-sql-database-as-user-dotnet)

There is a scope spelling nuance to validate rather than normalize away. Local `fabricQueryR/R/auth.R` uses `https://database.windows.net//.default`. Microsoft SQL Server documentation identifies the resource audience as `https://database.windows.net/`, while some Microsoft samples use single slash. Entra documentation says `.default` is appended to the exact resource identifier and explains that resources ending in slash can require a second slash. `.default` can be used in delegated flows; it is not synonymous with application identity. Consent grants permission to the client, and does not create SQL principals or grant tables. [Microsoft: scopes, `.default`, and trailing slashes](https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc#trailing-slash-and-default)

Design recommendation: store resource identifier, token request scopes, authority/cloud, and permitted target hosts as separate profile fields. Preserve the working local SQL profile during initial migration and explicitly test both request spellings against the desired tenants/services before selecting a canonical public default. Do not accept a Graph, Fabric REST, or ID token for a SQL connection.

| Literal request | Meaning for this design |
| --- | --- |
| `https://database.windows.net/user_impersonation` | Named Azure SQL delegated permission demonstrated by Microsoft's user-access tutorial; requires the relevant application registration and consent |
| `https://database.windows.net/.default` | Request the application's granted permissions for this resource; demonstrated by Microsoft Azure SQL user-token examples |
| `https://database.windows.net//.default` | Existing Fabric package profile; preserves a trailing slash in the resource audience in the MSAL parsing case described by Microsoft maintainers |

An archived MSAL maintainer migration-guide revision specifically describes the SQL double-slash case for a resource expecting an audience ending in slash. That historical explanation supports preserving existing profile strings literally, rather than collapsing slashes. It does not establish that every tenant/service accepts every alternative spelling today. [Microsoft MSAL maintainers: archived resource trailing-slash explanation](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/wiki/Adal-to-Msal/9465551e6d604956481021cdefc8217eb481292d)

## R odbc does expose externally supplied Azure tokens

The official `odbc` reference documents `attributes` as pre-connect connection attributes and specifically supports an `azure_token` scalar for Microsoft SQL Server, with reduced compatibility for non-Microsoft drivers. The documentation site inspected reports version 1.7.1. This resolves the question of whether an arbitrary supplied valid Entra SQL token has a supported R interface: it does. [odbc connection attributes](https://odbc.r-dbi.org/reference/ConnectionAttributes.html), [odbc DBI connection method](https://odbc.r-dbi.org/reference/dbConnect-OdbcDriver-method.html)

The upstream changelog records introduction of this Azure token connection-attribute interface in **odbc 1.3.4**, released 17 January 2023. That is the verified feature minimum; 1.7.1 is the current release observed, not the minimum version required solely for this capability. Set any higher package support floor based on the actual APIs used and validation results. [odbc release history](https://odbc.r-dbi.org/news/index.html)

```r
# Adapter sketch: token comes from a session-scoped delegated credential.
con <- DBI::dbConnect(
  odbc::odbc(),
  driver = "ODBC Driver 18 for SQL Server",
  server = "tcp:configured-server.database.windows.net,1433",
  database = "configured-database",
  Encrypt = "yes",
  TrustServerCertificate = "no",
  attributes = list(azure_token = sql_token)
)
```

Microsoft specifies `SQL_COPT_SS_ACCESS_TOKEN`, a pointer attribute with a length-prefixed, zero-padded token representation; it has no connection-string keyword. With this attribute, the connection string must omit `UID`, `PWD`, `Authentication`, and `Trusted_Connection`. Version 13.1 supported this on Windows; later driver versions support it across platforms. Microsoft also documents token-buffer lifetime and native pooling implications. [Microsoft ODBC: access-token authentication](https://learn.microsoft.com/en-us/sql/connect/odbc/using-azure-active-directory?view=sql-server-ver17#authenticating-with-an-access-token)

The upstream C++ implementation inspected converts the R string to that representation and sets the native attribute. Reuse the published R interface rather than constructing native buffers in shinyOAuthDB. [odbc token serialization source](https://github.com/r-dbi/odbc/blob/main/src/utils.cpp)

Remaining validation is operational: the installed R package and native driver versions, Windows/Linux deployment, trusted TLS, native pooling behavior, token expiry on an existing connection, reconnect with a fresh token, and two users connecting in one R process. The documented interface is verified; live behavior for this package is not.

Native ODBC pooling can reuse a physical server connection after a DBI handle disconnects. Therefore one DBI handle per operation does not by itself guarantee fresh server authentication. Require disabled native pooling until its identity partitioning/revalidation is tested. Microsoft documents `SQL_CP_OFF` as disabling pooling; this is an environment/process setting, not an ordinary SQL connection-string option. [Microsoft: Driver Manager connection pooling](https://learn.microsoft.com/en-us/sql/odbc/reference/develop-app/driver-manager-connection-pooling?view=sql-server-ver17)

## Fabric SQL: keep service behavior in fabricQueryR

Fabric SQL analytics endpoints and Warehouses use TDS on TCP 1433, accept Entra user/service principals, and apply platform object permissions. SQL authentication and MARS are unsupported. Since May 2026, omitting the initial catalog connects to a `master` context; specifying the actual item database remains preferable for direct queries. Transient service changes can require reconnecting. [Microsoft: Warehouse connectivity](https://learn.microsoft.com/en-us/fabric/data-warehouse/connectivity)

A user must have workspace-role or specific-item access; item connection permission does not automatically mean access to all data, and T-SQL grants/denies can refine permissions. Keep these settings in deployment guidance and verify that discovery and data operations operate under the same user. [Microsoft: Fabric SQL authentication and permissions](https://learn.microsoft.com/en-us/fabric/data-warehouse/entra-id-authentication#workspace-setting)

Observed local reuse opportunities in `../fabricQueryR/R/fabric_sql_connect.R`:

- `fabric_sql_connection_info()` already resolves discovery objects, copied connection strings, catalog, port, and target type.
- `fabric_sql_connect()` supports token strings/providers and returns an existing backend's `DBIConnection`.
- The ODBC branch already injects `attributes = list(azure_token = token_value)` inside the retry loop, refreshing the credential on retries.
- `fabric_sql_odbc_options()` merges permitted caller attributes, prevents overriding `azure_token`, and rejects conflicting authentication, DSN, target, driver, and TLS inputs.
- TLS defaults, disabled MARS, driver availability checks, and Fabric-specific transient error handling are already present.

Initial recommendation: shinyOAuthDB should supply a session-bound token provider to the public `fabricQueryR` functions. Reusing public interfaces avoids copying thousands of lines of endpoint parsing, SQL parameter handling, and result conversion. If shared SQL transport is subsequently moved here, make the ownership decision explicit and turn the old Fabric function into a compatibility wrapper. Avoid both packages implementing independent evolving copies.

### Optional ADBC path

The ADBC Driver Foundry `mssql` driver documents pre-acquired token authentication through `fedauth=ActiveDirectoryServicePrincipalAccessToken` with the token as a password field. Despite that mode's name, its documentation explicitly accepts user tokens as well as service-principal tokens. The caller must handle refresh. URI embedding creates a redaction concern. [ADBC mssql token connection](https://adbc-drivers.org/drivers/mssql/#connecting-with-a-pre-acquired-access-token)

Fabric compatibility was introduced in mssql driver 1.5.0 on 7 July 2026; the page currently lists 1.6.2. Keep this an optional transport and retain an appropriate minimum external driver version. [ADBC mssql changelog](https://adbc-drivers.org/drivers/mssql/changelog.html)

Local Fabric code already builds this URI and checks the connected driver version. It requires `adbi`, `adbcdrivermanager`, and optionally `nanoarrow`; its comments note `adbi` CRAN archival and R-universe installation. Those installation statements are local observations, and should be rechecked before publishing user installation instructions.

## SQL Server on premises: conditional native Entra support

SQL Server 2022 and later supports Entra authentication for Windows/Linux installations, including access tokens whose SQL audience is `https://database.windows.net/`. The overview describes Azure Arc plus the SQL extension, an Azure VM route through the SQL IaaS extension, and a manual Windows route without Arc. Failover cluster instances are excluded by the overview. Do not advertise arbitrary on-premises SQL Server as OAuth-capable. [Microsoft: SQL Server Entra overview](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/azure-ad-authentication-sql-server-overview?view=sql-server-ver17)

The Arc tutorial includes server application registration, directory-reading permissions, a suitable certificate, network reachability to Entra, an Entra administrator, and creation of external logins/users. Some setup steps vary by SQL Server version. These are DBA/server prerequisites, distinct from the Shiny OAuth application's client registration and delegated permissions. [Microsoft: Arc Entra setup](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/entra-authentication-setup-tutorial?view=sql-server-ver17)

The Windows route explicitly supports SQL Server 2022+ without Azure Arc, with certificate installation, the required library, server-side app registration, Graph permissions, registry configuration, and Azure network connectivity. A package should link this administrator workflow, not mutate it automatically. [Microsoft: Windows setup without Azure Arc](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/microsoft-entra-authentication-sql-server-enable-without-arc?view=sql-server-ver17)

Recommended target capability: `mssql_entra`, with a deployment declaration that Entra is configured. A compatibility diagnostic can check driver availability and attempt a user-authorized connection; a hostname or version string alone cannot establish server-side identity support. Windows integrated authentication uses separate mechanisms and does not automatically inherit the browser user's OAuth identity in a hosted Shiny process.

## Azure PostgreSQL: a good initial adapter

Azure Database for PostgreSQL Flexible Server can enable Entra authentication, provision an Entra administrator, and map database roles to Entra identities. The server validates the token and associates it with the unique Entra user ID rather than trusting the supplied display name. Database grants remain ordinary PostgreSQL grants. Group login may expose the group role as the SQL username even though the credential belongs to an individual member; do not promise that `current_user` always equals the user's email. [Microsoft: PostgreSQL Entra concepts](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-concepts)

The public-cloud token resource is `https://ossrdbms-aad.database.windows.net`. Microsoft documents passing the user's access token as the PostgreSQL password and supports ordinary libpq clients. Individual roles or provisioned group roles must exist, and role-name spelling matters. Acquire a fresh token shortly before connecting. Sovereign clouds need their cloud-specific resource. [Microsoft: configure Entra PostgreSQL](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure)

Microsoft examples show the v2 scope `https://ossrdbms-aad.database.windows.net/.default`. This profile differs from Microsoft SQL even though both use Entra. [Microsoft: PostgreSQL application connection scopes](https://learn.microsoft.com/en-us/azure/service-connector/how-to-integrate-postgres)

`RPostgres::Postgres()` accepts `user` and `password`, forwarding additional libpq parameters through `...`. Therefore the adapter can pass the token directly as `password`, with configured host, database, port, database role, and TLS options, and return the native `DBIConnection`. [RPostgres connection reference](https://rpostgres.r-dbi.org/reference/Postgres.html)

```r
# Adapter sketch; database_role is an approved mapping, not a trusted UI field.
con <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "configured-server.postgres.database.azure.com",
  dbname = "configured-database",
  user = database_role,
  password = postgres_token,
  sslmode = "verify-full",
  sslrootcert = configured_ca_bundle
)
```

Recommendation: use direct connection arguments instead of process-wide `PGPASSWORD` or `PGUSER`, which would be unsuitable for multiple Shiny sessions. Keep mapping policy configurable for individual/group roles and prefer stable identity metadata in the application credential context. Test server membership rejection, individual and group role behavior, and the revocation delay of token/group configuration in the actual deployment.

RPostgres uses libpq. This research verified the current `password`/additional-parameters interface, but did not establish a historical minimum RPostgres release for this adapter. Azure's token-as-password mechanism does not require the PostgreSQL 18 OAuth protocol. A usable libpq build, network access to the configured PostgreSQL endpoint, trusted server certificate/CA configuration, and enabled Entra role mapping remain prerequisites. [RPostgres project and native dependency](https://github.com/r-dbi/RPostgres)

## PostgreSQL 18 native OAuth: real capability, incomplete R bridge

PostgreSQL 18 introduces an OAuth bearer authentication configuration with issuer, scope, validator, and optional identity mapping. The token's provider must match the server's configured trust; there is no universal PostgreSQL audience/scope. Requested database usernames are matched against the validator's authenticated identity or an explicit mapping. `delegate_ident_mapping` hands additional role-authorization responsibility to the validator and should not be a casual default. [PostgreSQL 18 OAuth authentication](https://www.postgresql.org/docs/18/auth-oauth.html)

PostgreSQL supplies validator infrastructure, not a built-in universal validator for Entra/Okta/Keycloak. A deployed module must perform provider-specific validation. [PostgreSQL OAuth validator modules](https://www.postgresql.org/docs/18/oauth-validators.html)

The validator must validate the token, authorize the client to access the database, and authenticate the end user. Signature/introspection checks, issuer, audience, expiry, scopes, and role mapping therefore belong to configured server infrastructure. Merely decoding a JWT in the R client does not reproduce this guarantee. [PostgreSQL validator responsibilities](https://www.postgresql.org/docs/18/oauth-validator-design.html)

libpq 18 offers an optional built-in device authorization flow; that built-in flow is unavailable on Windows. Custom flows use the C `PQsetAuthDataHook` API, including a bearer-token request hook that can return an already acquired token. That is the promising transport for a shinyOAuth credential. Passing an OAuth token as `password` is not documented as the native PostgreSQL 18 OAUTHBEARER injection mechanism. [PostgreSQL libpq OAuth](https://www.postgresql.org/docs/18/libpq-oauth.html)

The current RPostgres connection source inspected calls `PQconnectdbParams()` with strings; its public API does not expose the authdata hook. The source also uses `PQreset()` during a broken-connection recovery, which matters for adapters holding an expiring password token. This establishes an integration gap, not proof that every possible R build cannot use OAuth. [RPostgres connection source](https://github.com/r-dbi/RPostgres/blob/main/src/DbConnection.cpp)

That recovery is not limited to session reuse: each newly created RPostgres result checks the connection. Audit automatic reset before claiming uninterrupted scoped transaction ownership; retaining one R connection object does not prove the underlying server session remained the same. [RPostgres result construction](https://github.com/r-dbi/RPostgres/blob/main/src/DbResult.cpp)

Recommendation: first seek an upstream RPostgres extension for a per-connection token provider/hook. An independently compiled helper must use the same loaded libpq, account for the library-wide hook and previous hook chain, associate tokens with the correct connection/session, and remain compatible with Windows/Linux builds. Do not ship a process-global one-user token hook as a shortcut. Alternatively permit a custom `connect` adapter that uses an organization's already tested OAuth-aware driver, without promising built-in native support.

PostgreSQL 17's native authentication list includes password, GSSAPI/SSPI, LDAP, certificate and other methods, with no native OAuth entry. A deployment may add extensions/proxies, but the application must know their actual credential and identity contracts. [PostgreSQL 17 authentication methods](https://www.postgresql.org/docs/17/auth-methods.html)

## Shared design and validation recommendations

These recommendations are design deductions from the capabilities above, not additional vendor guarantees.

| Dependency/configuration | Verified requirement versus draft recommendation |
| --- | --- |
| R SQL token injection | `odbc >= 1.3.4` introduces the feature; newer support floor can be chosen after checking required APIs |
| Microsoft native ODBC driver | 13.1 supports token attribute on Windows; subsequent versions support other platforms; draft chooses Driver 18+ for deployment consistency |
| ODBC manager | Windows provides a manager; deploy unixODBC for the documented Linux/macOS R stack |
| Fabric ADBC | External mssql driver 1.5.0+ for Fabric support; currently observed driver version 1.6.2 |
| Azure PostgreSQL | RPostgres/libpq password interface, Entra-enabled Flexible Server, provisioned database role; exact minimum RPostgres package version not established |
| Native PostgreSQL OAuth | PostgreSQL 18 and OAuth-capable libpq/client build, configured server validator, compatible token flow; R bearer hook remains unresolved |

Network connectivity is separate from OAuth: configured private/public SQL/PostgreSQL endpoints must be reachable by the Shiny host/workers, the database may need Entra/Graph egress for its setup, and the application needs its configured authorization/token endpoints. A browser login succeeding does not prove that any of those data-plane routes works.

1. Separate authentication resource profiles from transport adapters and target configuration. SQL ODBC, PostgreSQL password-token, HTTP bearer and native OAUTHBEARER are different injection contracts.
2. Require a delegated session credential throughout the shipped design. A token provider should receive the target resource requirement, preserve the session's stable identity, and return token/expiry metadata without exposing secrets in ordinary printing. Documented service-principal capability above explains vendor transport behavior; it is not a proposed package mode.
3. Return existing DBI connections for normal database work; rely on `DBI`, `dbplyr`, and backend behavior for queries, identifiers, result fetching and transactions. Do not build a second database abstraction merely to pass a token.
4. Keep live connections, reconnect factories and cached data scoped to an identity and authorization context. Include configured role and target in cache/pool keys; never share one SQL connection between different principals. Close connections on logout and Shiny session end.
5. Refresh for new connections; treat active-connection expiry and permission-change behavior as backend-specific. If strict authorization freshness is needed, expose bounded connection lifetime. Never claim immediate external revocation solely because an application refreshed a token.
6. Retry only operations whose replay contract is known. Connection establishment is safer to retry than an arbitrary user SQL statement, which might execute before the connection reports failure. Preserve transaction state explicitly and do not silently move a transaction to a new connection.
7. Avoid automatic CLI/cache/default credential fallback inside delegated session mode: it could select the app host's identity. Driver-owned interactive authentication is also a different workflow from the existing browser session.
8. Protect tokens from logging and prevent extra connection options from overriding authentication, the validated endpoint, or TLS. Consider the native ODBC manager's pooling separately from the R `pool` package.
9. Share query/task lifecycle without sharing live DBI connections between workers. Create the connection in the worker that uses it; associate cancellation, cleanup, completion and cached output with the initiating session and delegated identity. Resolve any interactive reauthorization in the main Shiny session, then explicitly hand off only the short-lived credential needed for the approved target. A failed or expired task must never substitute a host/application identity.

Before marking an adapter supported, exercise two real users with different permissions in one R process; compare server-side session identity and allowed/denied tables or rows; test token expiry and reconnect; verify logout cleanup and worker handoff; inspect errors/printed objects for secrets; and test a deliberate wrong-audience token. PostgreSQL native OAuth additionally requires server-validator and R-hook integration tests. None of these live checks was performed during this research.
