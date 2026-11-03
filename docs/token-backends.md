# PostgREST, StarRocks, and ClickHouse

Implementation research and validation from 3 November 2026.

## PostgREST

`oauth_db_postgrest_api()` uses the existing session-bound authorization
provider and httr2. PostgREST's [bearer authentication](https://docs.postgrest.org/en/stable/references/auth.html)
accepts externally signed JWTs and switches to the database role extracted
from the token. PostgreSQL grants and row policies enforce authorization.
There is no universal OAuth registration preset: each deployment supplies
its issuer, audience, scopes, and role mapping.

The API client exposes table selection, POST function calls, and native
requests. Schema headers follow the request method. Pagination is explicit
because the [server may cap each page](https://docs.postgrest.org/en/stable/references/api/pagination_count.html).
GET and HEAD refresh once after HTTP 401. Other methods never replay,
since [functions can modify data](https://docs.postgrest.org/en/stable/references/api/functions.html).
Requests stay pinned to their starting authorization and reject redirects
and responses returned after authorization changes.

Tests cover request shapes, exact JSON integers, schema headers, counts,
token rotation, account changes, sign-out, retry policy, and invalid inputs.
A live check used PostgREST 16.5 and PostgreSQL 16 in disposable containers,
behind a local HTTPS proxy with a private CA. Two signed JWT roles saw
different rows under a PostgreSQL row policy. RPC identity, exact 64-bit
integers, Content-Range, a denied write, account switching, and sign-out
passed. This tested database tokens, not an interactive identity-provider
login. Windows R 4.5.1 used curl 7.0.0 with its OpenSSL 3.5.0 backend;
the installed Schannel backend did not accept the fixture's private CA
file. No certificate was added to the Windows trust store.

## StarRocks

`oauth_db_starrocks()` uses MySQL Connector/ODBC's documented
[`openid-token-file` option](https://dev.mysql.com/doc/connector-odbc/en/connector-odbc-configuration-authentication.html).
The [StarRocks JWT plugin](https://docs.starrocks.io/docs/administration/user_privs/authentication/jwt_authentication/)
uses the matching MySQL client authentication protocol. Its
[3.5.0 implementation](https://github.com/StarRocks/starrocks/blob/3.5.0/fe/fe-core/src/main/java/com/starrocks/authentication/JWTAuthenticationProvider.java)
validates the token against the configured JWKS, principal, issuer, and
audience. StarRocks's HTTP SQL API documents Basic authentication, so this
backend uses the MySQL protocol instead of assuming HTTP bearer support.

The helper creates a private temporary token directory, removes it after
connection opening, verifies the server's TLS identity, and forbids DSNs,
option files, option-bit masks, and credential overrides. A random unusable
password prevents a password account from silently authenticating with an
empty password if its server configuration is wrong. Usernames may be
reactive; account and username changes replace the DBI connection.

Focused tests cover native argument mapping, token-file cleanup on success
and failure, connection reuse, account and username changes, sign-out,
credential restrictions, and the complete guide app before sign-in.
A live check loaded the actual MySQL Connector/ODBC 9.2 Windows driver
directly through its exported ODBC functions and connected to disposable
StarRocks 3.5.0 with a private TLS CA and an RSA JWKS. Two JWT users logged
in; table/view grants differed. Wrong audiences, a wrong TLS hostname, and
fallback to a password account were rejected. The token files were removed
immediately after opening connections. DBI/session integration was tested
separately with mocked connections: the Windows driver manager required a
system-registered driver, so a full live R/DBI connection was not tested.
