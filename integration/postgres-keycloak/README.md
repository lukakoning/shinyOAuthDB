# PostgreSQL and Keycloak browser test

Test browser sign-in and database permissions with a local Shiny app.
Alice and Bob run the same SQL query and receive different rows through
PostgreSQL row-level security. Docker runs the app, Keycloak, PostgreSQL 18,
and Chromium.

The app uses the public `oauth_db_postgres()` helper. The same Docker setup
can be launched through `source("playground/postgres/run.R")`; see the
[playground instructions](../../playground/postgres/README.md).

The fixture creates its own database and volumes. Its accounts and secrets
are public test data.

## Run

You need Docker Compose v2 with Linux containers and a shinyOAuth checkout
beside this repository. Use a current Compose v2 release with support for
the [reset tag](https://docs.docker.com/reference/compose-file/merge/#reset-value).
The test override keeps services off host ports, so a playground can stay running
while the tests execute. Arrange the checkouts as follows:

```text
GitHub/
  shinyOAuth/
  shinyOAuthDB/
```

From the shinyOAuthDB root on Windows:

```powershell
powershell -NoProfile -File integration/postgres-keycloak/run-integration.ps1
```

On Linux, macOS, or Git Bash:

```sh
bash integration/postgres-keycloak/run-integration.sh
```

The runner builds the images, starts the services, runs native and browser
tests, then removes the containers and volumes. The first build takes longer
because it compiles PostgreSQL and R dependencies. The containers supply
R and Chromium.

On Windows, `-SkipBuild` reuses images and `-Keep` retains services for
inspection, printing a cleanup command.

## Explore the app

Add `-Playground` on Windows, or set `OAUTHDB_PLAYGROUND=1` for the shell
runner. Open `http://localhost:18100` and sign in as `alice` or `bob`.
Their passwords are `alice-fixture-password` and `bob-fixture-password`.
Your browser may ask you to trust the fixture's local Keycloak certificate.

Use the app's controls to refresh tokens, sign out, change permissions, or
break a connection. Stop the runner to close it and clean up.

## What the tests cover

The browser tests sign Alice and Bob in at the same time and check their
row and table permissions, connection reuse, refresh, account changes, and
sign-out. Additional cases cover PKCE, wrong audiences, missing scopes,
role impersonation, and broken connections.

See [fixture SQL](sql/01-fixture.sql),
[identity mappings](config/pg_ident.conf), and
[authentication rules](config/pg_hba.conf) for the database setup.
PostgreSQL checks the token and role; the query does not filter by user in R.

## Runtime details

PostgreSQL/libpq 18.3 and Keycloak 26.6.1 are pinned in the build.
RPostgres 1.4.10 and shinyOAuthDB's native adapter link the same shared
libpq 18. The package is installed with native OAuth required, so a missing
adapter fails the lane. The adapter currently supports Linux; Windows and
macOS can run the Linux containers. See the [PostgreSQL guide](../../vignettes/postgres.Rmd)
for the supported build and connection lifetime.

The [native regression checks](native/tests/regression.R) exercise cleanup
and connection isolation against the installed package. The independent
[GitHub Actions lane](../../.github/workflows/postgres-integration.yaml)
runs the native and browser suites and records sanitized assertion counts
under `.generated/results.json`; any warning or skipped test fails the lane.

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
