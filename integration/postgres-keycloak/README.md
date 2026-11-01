# PostgreSQL and Keycloak browser test

Use this Docker fixture to test the complete path from browser sign-in to
database-enforced permissions. It runs Shiny, Keycloak, PostgreSQL 18, and
Chromium in containers. Alice and Bob run the same SQL query and receive
different rows through PostgreSQL row-level security.

The fixture creates its own database and volumes. Its accounts and secrets
are public test data.

## Run

You need Docker Compose v2 with Linux containers and a shinyOAuth checkout
beside this repository:

```text
GitHub/
  shinyOAuth/
  shinyOAuthDB/
```

From the shinyOAuthDB root on Windows:

```powershell
rtk proxy powershell -NoProfile -File integration/postgres-keycloak/run-integration.ps1
```

On Linux, macOS, or Git Bash:

```sh
bash integration/postgres-keycloak/run-integration.sh
```

The runner builds the images, starts the services, runs native and browser
tests, then removes the containers and volumes. The first build takes longer
because it compiles PostgreSQL and R dependencies. Host R and Chromium
installations are not needed.

On Windows, `-SkipBuild` reuses images and `-Keep` retains services for
inspection, printing a cleanup command.

## Explore the app

Add `-Playground` on Windows, or set `OAUTHDB_PLAYGROUND=1` for the shell
runner. Open `http://localhost:18100` and sign in as `alice` or `bob`.
Their passwords are `alice-fixture-password` and `bob-fixture-password`.
Your browser may ask you to trust the fixture's local Keycloak certificate.

The app exposes refresh, sign-out, permission changes, and broken-connection
controls. Stop the runner to close it and clean up.

## What the tests cover

The browser tests check PKCE sign-in, simultaneous Alice/Bob sessions,
row and table permissions, connection reuse, refresh, authorization replacement,
and sign-out. Negative cases check wrong audiences, missing scopes, role
impersonation, and broken connections.

See [fixture SQL](sql/01-fixture.sql),
[identity mappings](config/pg_ident.conf), and
[authentication rules](config/pg_hba.conf) for the database setup.
PostgreSQL checks the token and role; the query does not filter by user in R.

## Runtime details

PostgreSQL/libpq 18.3 and Keycloak 26.6.1 are pinned in the build.
RPostgres 1.4.10 and the [native token helper](native/README.md) link the same
shared libpq. The helper is Linux-only and installed only in the test image.
Production PostgreSQL native OAuth still needs a supported RPostgres token
interface; use `oauth_db_azure_postgres()` for Azure's Entra authentication.

The server uses Percona's `pg_oidc_validator` at commit
`ba9c4cb2dc9bd2e9779c7a33f7a30c9bb8c97862` with a fixture-specific
[audience check](patches/validator-audience.patch). Build provenance is in
`/opt/fixture-provenance` inside the images.

Services share a network namespace so the issuer is consistently
`https://localhost:18443/realms/shinyoauthdb`. Only Keycloak port 18443 and
Shiny port 18100 are published, on `127.0.0.1`. PostgreSQL stays internal.
Connections verify a generated test CA; automated Chromium trusts it in its
container profile.

See [PostgreSQL OAuth](https://www.postgresql.org/docs/18/auth-oauth.html)
and [Percona's validator](https://github.com/percona/pg_oidc_validator)
for the underlying server interfaces.
