# SAP HANA backend decision

Investigated on 8 November 2026. `oauth_db_hana()` provides SQL access to
SAP HANA Platform and SAP HANA Cloud through SAP's HANA ODBC driver. It
uses the existing optional odbc dependency and returns its native DBI
connection. No Java runtime, new R driver or separate token cache is needed.

## Authentication and transport

SAP documents [JWT authentication for on-premise and cloud HANA](https://help.sap.com/docs/SAP_DATA_SERVICES/e54136ab6a4a43e6a370265bf0a2d744/8d553b3a0aca45beb9f6dfb68185ebaa.html)
with an empty username and a JWT in the password field. The
[client authentication reference](https://help.sap.com/docs/SAP_HANA_CLIENT/f1b440ded6144a54ada97ff95dac7adf/811ec52440d64cd58ab08527d8ca25d3.html)
explains that providing both fields selects password mechanisms. The
adapter therefore sets `UID=""`, `PWD=<visitor access token>` and
`authenticationMethods=jwt` on every new native connection.

The database must trust the access token's issuer and signing keys, check
its audience and map the external identity to a database user. Follow
SAP's [JWT provider configuration](https://help.sap.com/docs/SAP_ASE_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/1c362387bc9e48a6a275146a11e1466e.html)
for the target edition. The helper checks compact signed-JWT shape only;
HANA authenticates the signature and applies database privileges. It does
not replace an access token with an ID token.

There is no universal SAP issuer, audience or SQL access scope. The source
guide uses shinyOAuth's existing OIDC discovery and OAuth client. A BTP
browser login or a client-credentials service token does not establish the
visitor identity that this integration requires. HANA Cloud data lake,
Datasphere application APIs and SAP business application APIs are separate
interfaces and are outside this adapter's scope.

## Connection settings and lifetime

The adapter constructs one `serverNode` from an explicit hostname or IPv4
address and port. `databaseName` selects an optional tenant;
`currentSchema` selects an optional initial schema. HANA Cloud normally
uses its database endpoint on port 443, as documented in SAP's
[ODBC setup guide](https://help.sap.com/docs/hana-cloud/sap-hana-cloud-getting-started-guide/connect-to-sap-hana-database-in-sap-hana-cloud-via-odbc).
Self-hosted SQL ports come from the database administrator.

TLS is mandatory. The connection sets `encrypt=true`,
`sslValidateCertificate=true` and `sslHostNameInCertificate` to the chosen
endpoint. An explicit trust store can be supplied for the client's TLS
provider. Additional arguments have an allowlist of R result and timeout
options; they cannot select another credential, routing rule or TLS policy.

The [SAP HANA Client 2.29 reference](https://help.sap.com/doc/b01bb8ddc72e41f795034092b9bf541d/2.29/en-US/SAP_HANA_Client_Interface_Programming_Reference_en.pdf)
documents automatic reconnect and its disabling property. The adapter
sets `reconnect=false` so reconnects go through the session helper and get
a current token. It neither retries failed SQL nor writes tokens to disk.
The driver receives the token as a password and may retain it in its
native handle; callers must obtain the connection through `con()`.

Ordinary token renewal preserves a valid database session. Authorization
replacement, sign-out, loss of required scopes and Shiny session end close
it. The shared lifecycle manager binds native handles to the owning session.

## Validation boundary

Tests exercise the real odbc connection-string builder up to its native
boundary, JWT rejection and attempts to override authentication or TLS.
Real SQLite DBI handles verify visitor isolation, current tokens on
reconnect and lifecycle cleanup. The HANA guide's complete app is checked
for construction and its signed-out behavior.

No SAP HANA ODBC driver or configured HANA service is available in this
environment. Live compatibility requires checking the mapped principal
and distinct database grants for two visitors, permission denial, expired
tokens, renewed-token reconnect and TLS verification on the chosen client
and database releases. No self-hosted Docker demo is claimed.
