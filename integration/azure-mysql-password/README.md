# Azure MySQL driver protocol check

This fixture exercises `oauth_db_azure_mysql()` with real MariaDB
Connector/ODBC and a TLS-enabled MySQL protocol server. It accepts synthetic
visitor tokens through `mysql_clear_password`; it doesn't contact Azure or
validate Entra JWTs. The server returns small fixture results rather than
running a MySQL database engine.

Install Docker and the MariaDB Connector/ODBC driver, then run from the
repository root:

```sh
Rscript --vanilla tools/check-azure-mysql.R "MariaDB ODBC 3.2 Driver"
```

The first argument is the registered driver name or full driver library
path. Additional arguments are R dependency-library directories.

The check builds its own container and temporary CA, publishes only on
IPv4 loopback with an assigned port, and removes the container afterward.
It checks the raw token, including a 12 KB token, verified TLS, certificate
and hostname rejection, account isolation, token renewal,
failed authentication, connection cleanup and denied queries. Its audit
file records token lengths and hashes, excluding token contents.

This simulator doesn't cover MySQL's full prepared-statement protocol.
Check DBI parameter binding and application SQL against the target database.
For a client running in a container that shares the fixture's network,
set `OAUTHDB_MYSQL_TEST_FIXTURE` to its mounted output directory and
`OAUTHDB_MYSQL_TEST_PORT` to `3306` to reuse an existing fixture.

Before claiming a live Azure deployment works, test two real Entra users,
the expected database identities and grants, a denied user, group mapping
if used, and reconnection after token renewal against that Azure server.
The [setup guide](../../vignettes/azure-mysql.Rmd) describes registration
and driver requirements.
