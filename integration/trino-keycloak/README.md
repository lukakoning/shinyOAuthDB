Run Trino OAuth2 integration with a real browser and the released RTrino client:

```sh
bash integration/local/run-integration.sh trino
```

On Windows:

```powershell
powershell -NoProfile -File integration/local/run-integration.ps1 -Backend trino
```

Docker Compose v2 with Linux containers and a sibling shinyOAuth checkout are
required. The runner builds its R/browser dependencies, starts pinned Trino 484
and Keycloak 26.6.1 images, and installs the current mounted package checkouts.
The GitHub Actions workflow caches the R/browser build and runs independently
of the other backend workflows. No cloud accounts or secrets are required.

Alice and Bob sign in using authorization code flow with PKCE. Queries use the
public `oauth_db_trino()` helper and native RTrino DBI objects. Trino's OAuth2
authenticator verifies the issuer, audience and signature. File access rules
apply row filters and separate table grants; the app submits the same SQL for
both users. Another-user impersonation must fail even with a valid token.
The suite also exercises native DBI fetching, refresh without replaying queries,
connection reuse, account replacement, logout, session end, and rejection of
modified, expired and wrong-audience credentials. Missing scopes block queries.
Value checks cover Unicode, typed nulls, exact bigint values, timestamps and
empty column schemas. Explicitly closing a native connection must cause the
public helper to reopen it under the same current account on the next read.

Only the fixture's provisioning client uses client credentials. It creates the
memory tables before tests. Browser acceptance queries always use Alice or Bob.
Keycloak authorization/token requests and Trino connections use verified HTTPS.
The test CA is trusted explicitly by Chromium, R and Trino's JVM. Internal coordinator traffic
also uses HTTPS and a fixture-only shared secret.
The Shiny app uses HTTP on its internal localhost callback. The fixture sets
`http-server.authentication.oauth2.max-clock-skew=0s` because the containers share
a clock, so the expiry probe can check rejection immediately after expiration.
Negative TLS listeners present untrusted and wrong-hostname certificates. The
public helper must reject both before sending HTTP, verified by request counts
on those listeners.

The coordinator is limited to a 1 GiB Java heap and uses a tiny in-memory catalog.
Every run gets a unique Compose project and publishes no host ports. Containers
and volumes are removed on success or failure. Use `-SkipBuild` on Windows or
`OAUTHDB_SKIP_BUILD=1` on Unix to reuse images. Sanitized assertion counts and
driver versions are written to `.generated/results.json`. Warnings and skips fail
the test job. This fixture validates Trino, not Starburst-specific features.

Validated locally on 2026-11-04: 65 passing browser assertions, with zero
failures, errors, warnings or skips. The complete Bash build-and-test runner
completed successfully against Docker Desktop's Linux engine.
