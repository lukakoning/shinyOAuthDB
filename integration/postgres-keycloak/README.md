# Self-hosted PostgreSQL OAuth integration

This opt-in Docker Compose fixture runs PostgreSQL 18, Keycloak and a real
Chromium-driven Shiny application. The application obtains delegated user
tokens through the current sibling shinyOAuth checkout, then uses shinyOAuthDB
and an ordinary RPostgres DBI connection. PostgreSQL validates the tokens and
enforces its own role grants and row-level security.

The fixture creates a separate database and Docker volumes. It does not connect
to your existing PostgreSQL server. Users, passwords and client secrets in this
directory are public test fixtures. This setup is for development, with a
locally generated CA and a narrow Linux-only native helper.

## Run

Requirements: Docker Compose v2 with Linux containers, network access for the
first image build, and the development `shinyOAuth` checkout beside this repo:

```text
GitHub/
  shinyOAuth/
  shinyOAuthDB/
```

From the shinyOAuthDB repository root on Windows:

```powershell
rtk proxy powershell -NoProfile -File integration/postgres-keycloak/run-integration.ps1
```

On Linux/macOS or from Git Bash:

```sh
bash integration/postgres-keycloak/run-integration.sh
```

The runner builds the images, generates TLS material, starts the isolated
services, waits for readiness, installs the current mounted R source packages
into a temporary container library, runs native regression and browser tests,
then removes that run's containers and volumes. The first build compiles
PostgreSQL, RPostgres and R dependencies and takes longer; subsequent builds
use Docker's cache. No host R packages or Chromium installation are needed.

Tests fail on missing prerequisites or any skipped scenario. Failures return
a nonzero exit status. The ordinary package test suite does not start Docker.

Windows options: `-SkipBuild` uses existing images; `-Keep` retains that run's
services for inspection and prints its project-specific cleanup command.

For the interactive Shiny playground, add `-Playground` (or on Linux/macOS set
`OAUTHDB_PLAYGROUND=1` before running the shell script). Open
`http://localhost:18100`, authorize `alice` or `bob`, then load their granted
rows. Passwords are `alice-fixture-password` and `bob-fixture-password`.
Refresh, logout, role/table denial and broken-connection controls use this same
fixture. Your host browser may ask you to trust the locally signed Keycloak
certificate; automated Chromium trusts the CA inside its container. Stop the
runner to close the app and clean up its stack.

## What is tested

| Scenario | Required result |
|---|---|
| Real browser sign-in | Authorization code flow with PKCE S256, using the public shinyOAuth module connection |
| Concurrent Alice/Bob sessions | The same SQL query returns only each role's own RLS-protected rows |
| Table permissions | Each role can read its own table and is denied access to the other role's table |
| Role impersonation | Alice's valid token cannot connect as Bob, or Bob's as Alice |
| Native connection reuse | Repeated reads preserve the PostgreSQL backend PID within one authorization |
| Real forced refresh | Keycloak refreshes the selected grant; cached data and the authorization generation stay stable; the next connection uses the new token |
| Logout and replacement | Saved results clear, the previous native connection closes and retained token providers fail |
| Wrong audience | A valid token for a different resource is denied by PostgreSQL |
| Missing database scope | The bridge denies before connecting; a separate native probe confirms PostgreSQL also rejects that token |
| Broken native connection | Subsequent direct DBI calls fail; libpq cannot start another login or substitute credentials |
| Native hook cleanup | The token hook is restored after success, errors and validation failures; unrelated connection metadata cannot consume its token |

Fixture SQL lives in [sql/01-fixture.sql](sql/01-fixture.sql), identity mappings
in [config/pg_ident.conf](config/pg_ident.conf), and authentication rules in
[config/pg_hba.conf](config/pg_hba.conf). The test application uses a fixed,
trusted mapping from the verified OIDC subject to `alice` or `bob`.
PostgreSQL independently checks that the token may authenticate that role.
No query adds an application-side user filter to imitate row-level security.
The Keycloak clients include its built-in `basic` scope so their access tokens
contain `sub`, the identity claim used by the database mapping. Their separate
`database.read` scope is the permission required by PostgreSQL; audience mappers
identify the resource for which each client obtains tokens.

## Network and certificates

Keycloak owns a shared Compose network namespace. PostgreSQL, the R test
process and Chromium use that namespace too, so they all resolve the exact
issuer `https://localhost:18443/realms/shinyoauthdb`. No hosts-file change is
needed. Only Keycloak port 18443 and the temporary Shiny callback port 18100
are published, on `127.0.0.1`. PostgreSQL port 5432 stays inside the namespace.

The TLS service generates a private test CA and server certificate in a
project-scoped volume. Provider requests and PostgreSQL connections verify
the CA; PostgreSQL connections use `sslmode = "verify-full"`. The browser
trusts this test CA through its private container profile.

## Reuse and remaining limits

PostgreSQL/libpq **18.3** is compiled from an archive with a checked SHA-256.
Keycloak **26.6.1** and the Debian base use pinned image digests. RPostgres
**1.4.10** is built against the same shared libpq as the
[integration-only native helper](native/README.md).

The server reuses Percona's `pg_oidc_validator` at commit
`ba9c4cb2dc9bd2e9779c7a33f7a30c9bb8c97862`. Its existing signature, issuer,
expiry and scope validation remains upstream code. The small checked-in
[audience patch](patches/validator-audience.patch) adds a required expected
audience for this fixture; an unset audience fails closed. Build provenance
is recorded inside the images under `/opt/fixture-provenance`.

RPostgres currently has no public method for injecting a pre-acquired native
OAuth token. `pgBearerHook` supplies one fixed token only during a synchronous
connection opening and returns an ordinary RPostgres connection. It checks
that both libraries use the same libpq and restores the previous hook on
unwind. The fixture libpq omits the optional built-in device-login module;
the Keycloak clients also disable device and password grants. Broken
connections must be discarded instead of resetting them with new credentials.

This proves the configured local browser-to-database path. The helper is not
installed as a production dependency and there is no general
`oauth_db_postgres()` constructor yet. Production native PostgreSQL support
still needs a supported RPostgres token-hook interface, platform/build testing,
and the deployment's own identity, TLS and authorization configuration.

References: [PostgreSQL native OAuth](https://www.postgresql.org/docs/18/auth-oauth.html),
[libpq auth hooks](https://www.postgresql.org/docs/18/libpq-oauth.html),
[Percona validator](https://github.com/percona/pg_oidc_validator), and
[the sibling Keycloak integration](../../../shinyOAuth/integration/keycloak/README.md).
