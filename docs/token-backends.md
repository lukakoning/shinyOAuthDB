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
