# SingleStore backend decision

Investigated on 9 November 2026. `oauth_db_singlestore()` connects to
self-managed SingleStore and SingleStore Helios through SingleStore's
ODBC driver. It uses the existing optional odbc dependency and returns
the native DBI connection. SQL and dbplyr stay with the existing client.

## Authentication

The [driver reference](https://docs.singlestore.com/cloud/developer-resources/connect-with-application-development-tools/connect-with-odbc/the-singlestore-odbc-driver/)
documents an explicit `JWT` connection property. In the reviewed
[Connector/ODBC 1.2.1 source](https://github.com/memsql/singlestore-odbc-connector/blob/v1.2.1/ma_connection.c),
that property becomes the connection password. Setting `BROWSER_SSO=0`
prevents browser authentication and keyring fallback, including after a
failed login. `IGNORE_KEYRING_SSO=1` additionally disables keyring storage.
No secondary password is supplied: this driver rejects combinations of
`JWT`, password and browser SSO.

SingleStore validates the JWT signature, configured audience and identity
mapping. The helper checks compact signed-JWT shape and supplies the
visitor's access token. It does not exchange it for a portal credential
or substitute an ID token. The provider must issue tokens trusted by the
database. There is no universal issuer, audience or SQL access scope, so
the guide uses shinyOAuth's existing OIDC configuration.

The default SQL username is `*`, allowing SingleStore to select the user
from the token. The driver release notes require SingleStore 8.1.20 or
later for that mapping. Explicit usernames, including reactive usernames,
must match the database's JWT mapping. Account and username changes retire
the old native connection.

## TLS and driver configuration

The reviewed driver enables `MYSQL_OPT_SSL_ENFORCE` when a CA, certificate
or cipher is supplied. `SSLVERIFY` separately enables certificate and
hostname verification. The helper therefore requires a nonempty `ssl_ca`
argument and sends both `SSLCA` and `SSLVERIFY=1`.

`USE_MYCNF=0` disables MySQL option-file discovery, `AUTO_RECONNECT=0`
disables reconnects with the driver's copied credential, and `NO_PROMPT=1`
disables driver prompts. Additional options have an allowlist of result
and timeout settings. DSNs, alternative credentials, socket routing,
initial SQL, TLS overrides and option bitmasks are rejected before token
acquisition. Native errors use the shared ODBC connector so retained
connection calls do not contain literal tokens.

## Session lifetime

The helper selects MySQL's ODBC connection class with `dbms.name="MySQL"`.
The live probe established that generic dbplyr SQL uses double-quoted
identifiers which SingleStore rejects in its default SQL mode. The MySQL
class supplies compatible identifier quoting and translations.

The live probe also found that `DBI::dbIsValid()` can remain true after
the server terminates a connection. A SHA-256 token reuse key therefore
replaces the cached connection on its next access after token renewal,
without notifying consumers to replay completed queries. This avoids
reopening with the driver's obsolete copied credential. Automatic driver
reconnects remain disabled. Sign-out, permission loss, account changes and
Shiny session end close cached handles. Pending results and transactions
should finish before obtaining another connection after token renewal.

## Validation

Unit tests exercise the real ODBC connection builder, malformed tokens,
option injection, named targets, literal scopes and error serialization.
SQLite-backed native handles check isolation, username changes and cleanup.
The guide's complete app is constructed and its signed-out query checked.

The [SingleStore fixture](../integration/singlestore-jwt/README.md) uses
the official driver and a real self-managed server with disposable keys,
JWT users and verified TLS. Browser sign-in, Helios portal tokens and a
live Helios workspace require separate deployment validation.
