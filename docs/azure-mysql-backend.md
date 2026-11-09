# Azure Database for MySQL backend

## Driver choice

Azure MySQL Flexible Server accepts a visitor's Entra access token as the
database password through `mysql_clear_password`. Microsoft documents the
resource audience as `https://ossrdbms-aad.database.windows.net` and requires
the client to send the token unchanged. See the
[Entra setup guide](https://learn.microsoft.com/en-us/azure/mysql/security/security-how-to-entra).

Use MariaDB Connector/ODBC 3.1 or later through R's `odbc` package. MariaDB's
client library supplies the cleartext plugin, and its driver exposes
`FORCETLS=1` and `SSLVERIFY=1` for encrypted, verified connections.
[Driver options](https://mariadb.com/docs/connectors/mariadb-connector-odbc/mariadb-connector-odbc-guide)
and [cleartext plugin behavior](https://mariadb.com/docs/server/reference/plugins/authentication-plugins/authentication-with-pluggable-authentication-modules-pam/authentication-plugin-pam)
describe those settings.

MySQL Connector/ODBC 9.5.0 crashed before contacting the server when supplied
a 2 KB synthetic password through SQLDriverConnect. Both its ANSI and
Unicode drivers reproduced the failure. A native GDB backtrace located
the overflow in `optionStr::set_remove_brackets`; the
[upstream implementation](https://github.com/mysql/mysql-connector-odbc/blob/trunk/util/installer.cc)
copies option values into a fixed 1024-element buffer. Quoting the token
didn't prevent the crash. This is a blocker for ordinary Entra tokens, so
the Azure helper rejects identifiable MySQL Connector/ODBC driver names.

## Connection behavior

`oauth_db_azure_mysql()` supplies only the current visitor token and the
configured database identity. It disables option files, prompts and driver
reconnection, and uses a small allowlist for optional result settings.
The connection cache uses a token hash, so the next access after renewal
replaces the native connection without replaying completed reactive queries.
Username changes, account replacement, permission loss, sign-out and Shiny
session end follow the existing session cleanup behavior.

The Microsoft preset uses the named target `mysql`. Like Azure PostgreSQL,
it requests `.default` on its own and `user_impersonation` when combined
with other Microsoft services. The two database targets share an audience;
they retain their own authorization records and configured requirements.

## Validation and limits

The [local fixture](../integration/azure-mysql-password/README.md) passed
with MariaDB Connector/ODBC 3.1.15 and R odbc 1.7.2 on Linux. It accepted a
12005-byte synthetic token intact and checked encrypted connections,
certificate rejection, token replacement, separate visitors and failed
authentication. Unit tests exercise the real shinyOAuth authorization
contract and DBI connection cleanup, and construct the complete guide app.

The fixture implements the MySQL authentication protocol and small query
responses. It doesn't validate Entra JWTs or execute real database grants.
Validate the app registration, Azure networking, user/group mapping,
permission denial and application SQL against a real Azure deployment.
The [user guide](../vignettes/azure-mysql.Rmd) contains the setup steps.
