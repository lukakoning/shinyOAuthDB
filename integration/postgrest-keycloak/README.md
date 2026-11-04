Run real browser sign-in and PostgREST authorization locally:

```sh
bash integration/local/run-integration.sh postgrest
```

On Windows:

```powershell
powershell -NoProfile -File integration/local/run-integration.ps1 -Backend postgrest
```

Docker Compose v2 with Linux containers and a sibling shinyOAuth checkout are
required. The containers supply R, Chromium, PostgreSQL 18.3 and PostgREST 16.5.
The runner installs the mounted package sources into an isolated library.
Use `-SkipBuild` on Windows or `OAUTHDB_SKIP_BUILD=1` on Unix to reuse images.

Alice and Bob sign in through Keycloak using authorization code flow with PKCE.
The public `oauth_db_postgrest_api()` helper calls a security-invoker RPC;
PostgreSQL row-level security restricts the same query to each user's rows.
The suite checks separate browser sessions, denied table access, token refresh,
modified/expired/wrong-audience tokens, account replacement, logout and session end.
Missing operation scopes must prevent queries. These fixture accounts and
passwords are public test data; password grants are disabled.

Round trips cover quoted Unicode arguments, JSON nulls, PostgreSQL's largest
signed bigint, timestamps and empty results. Disposable RPCs record writes
under row-level security. After PostgreSQL commits, the HTTPS proxy injects
HTTP 503, a dropped connection or a response delay longer than the client's
timeout. Each API call must report the expected HTTP/transport failure, and
the SQL counter must show exactly one write.

A separate test uses the fixture administrator to revoke Alice's Keycloak
session, then forces a real refresh. Keycloak returns `invalid_grant`; under
the module's default finite-session policy, local authorization and the retained
API client become unusable without replaying the query. Signing in as Bob must
recover with a new authorization and Bob's rows. The administrator's password
grant is confined to fixture control; browser clients use PKCE.

HTTPS terminates at a local proxy using a generated CA trusted by the test runner
and Chromium. PostgREST itself validates the JWT using Keycloak's public JWKS.
Keycloak's internal HTTP port serves public keys within the isolated fixture;
browser login, token exchange and package API requests use verified HTTPS.
Separate listeners present an untrusted certificate and a trusted certificate
for the wrong hostname. Both must be rejected before any HTTP request reaches
those listeners; a trusted listener provides the readiness control.

No host ports are published. Every run uses a unique Compose project, and removes
its own containers and volumes even on failure. This suite and the PostgreSQL
workflow can run independently. Sanitized counts are written
to `.generated/results.json`; failures, warnings and skips fail the job.

Validated locally on 4 November 2026: 81 passing assertions, zero failures,
errors, warnings or skips, using the pinned server images and current checkouts.
