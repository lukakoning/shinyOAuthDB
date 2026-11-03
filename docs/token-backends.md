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

## ClickHouse

`oauth_db_clickhouse_api()` sends each visitor's bearer token to the
[HTTPS query interface](https://clickhouse.com/docs/interfaces/http).
The [JWT availability guide](https://clickhouse.com/blog/introducing-jwt-authentication-in-clickhouse-cloud)
requires Cloud Enterprise and service 26.4 or later for custom identity
providers, or 26.8 for EC keys. A Cloud management API key or an ordinary
self-hosted server is not interchangeable with that authentication path.

The helper uses the same session-bound HTTP provider as PostgREST. SQL
goes in the POST body and typed parameters use `param_` URL fields.
Scalars are escaped separately; `I()` preserves native encoded values
such as array literals. JSONCompact keeps column order and duplicate
names, with quoted large integers and decimals. Full JSON parsing and
metadata checks reject incomplete result streams. Statements are never
replayed automatically, including after HTTP 401.

Tests cover request serialization, precise and nested result types,
empty results, token renewal between operations, account isolation,
sign-out, HTTP failures, and incomplete/error responses. Live HTTP SQL
checks used ClickHouse 26.1.2.11 behind a disposable HTTPS fixture proxy
that mapped test bearer strings to separate database users. Escaped
strings, nullable values, exact integers and decimals, dates, encoded
arrays, DDL, inserts, empty selections, denied table access, and account
switching passed. The proxy was only a transport fixture: native
ClickHouse Cloud JWT verification and interactive provider login were
not tested because no configured Cloud service was supplied.

## Package validation

On Windows 11 with R 4.5.1, the full source test suite passed 1,496
assertions with no skipped scenarios. `tools/check-package.R` installed
the package in a temporary library, built its vignettes, and completed
`R CMD check --no-manual` with zero errors, warnings, or notes.
`tools/check-docs.R` parsed 60 R documentation blocks and verified 123
local links. The dependency library was temporary; it included shinyOAuth
0.7.0, httr2 1.3.0, and the optional packages needed by existing backends.
