Run StarRocks JWT integration using the real MySQL Connector/ODBC OpenID plugin:

```sh
bash integration/local/run-integration.sh starrocks
```

On Windows:

```powershell
powershell -NoProfile -File integration/local/run-integration.ps1 -Backend starrocks
```

Docker Compose v2 with Linux containers and a sibling shinyOAuth checkout are
required. Containers supply StarRocks 3.5.0, Keycloak 26.6.1, Chromium, R, odbc,
and MySQL Connector/ODBC 9.5.0 with `authentication_openid_connect_client`.
Server images and the native driver archive are pinned; the driver download is
verified against its SHA-256. The current package checkouts are installed fresh
into an isolated library. No cloud accounts or private credentials are needed.

Alice and Bob sign in through real browser authorization code flow with PKCE.
The public `oauth_db_starrocks()` helper supplies their access JWT to the native
ODBC plugin using its temporary file. StarRocks independently validates issuer,
audience, signature, expiry and username. A protected view evaluates the database
principal and filters rows on the server, and the users have separate table
grants. The app executes identical SQL for both users; neither user can read the
base table or the other user's private table.

The suite checks real connection reuse across refresh, account replacement,
logout, session end, missing scopes, wrong audiences, modified and expired tokens,
and rejection of another username with the current user's valid token. An
empty-password account must not become a fallback when JWT authentication is
unavailable. Temporary JWT directories must be gone after the native probes.
The native driver also round-trips quoted Unicode parameters, typed nulls,
bigints, timestamps and empty column schemas. Closing the native connection
must make the helper open a new connection under the current account.
The helper sets `NO_SSPS=1` to use the driver's client-side prepared statements.
The server-side prepared path could stall on these typed queries with this
pinned server/driver combination; the round-trip checks cover the replacement.

ODBC verifies the generated CA and server identity. StarRocks requires secure
transport. Keycloak's internal HTTP endpoint serves its public JWKS only inside
the isolated network; browser login and token exchange use verified HTTPS.
The admin passwordless root account only provisions this disposable local server.
Acceptance queries use the two JWT-authenticated users.
The same StarRocks server must reject connections with an untrusted CA or a
hostname that does not match its certificate.

The server uses a 1 GiB FE heap and a 1 GiB BE memory limit. Each run has a unique
Compose project, publishes no host ports, and removes its own containers and
volumes even on failure. Use `-SkipBuild` on Windows or `OAUTHDB_SKIP_BUILD=1` on
Unix to reuse images. The independent GitHub Actions workflow caches the R/browser
build and uploads `.generated/results.json`; test failures, warnings and skips
fail the job.

Validated locally on 2026-11-04: 67 passing browser assertions, with zero
failures, errors, warnings or skips. The Bash runner completed successfully
against Docker Desktop's Linux engine.
