# Integration checks

The ordinary package suite uses local fixtures and mocked cloud responses.
Use these additional checks to verify browser sign-in or access to a real
database.

## Local browser sign-in and PostgreSQL

The [PostgreSQL/Keycloak fixture](../../integration/postgres-keycloak/README.md)
runs in Docker. It checks real OAuth sign-in, database-enforced user permissions,
refresh, and sign-out. Its native PostgreSQL token helper is for this fixture
only; the Azure PostgreSQL helper uses a different connection method.

## Fabric sandbox

Follow the [Fabric app instructions](../../playground/fabric/README.md) to
start the prepared sandbox, then run:

```sh
Rscript tools/check-fabric-sandbox.R
Rscript tools/check-fabric-browser.R
```

These verify queries and app rendering with the shared sandbox application.
They do not test delegated visitor sign-in.

## Your own cloud database

`run-live.R` checks a backend with two existing delegated user tokens.
It verifies native connection reuse where applicable, user replacement,
expected query results, and sign-out. Browser sign-in, consent, and token
refresh need a separate browser test.

1. Install the database client and driver. Set the backend's connection
   variables listed in [source-config.R](source-config.R).
2. Give users A and B distinct access to fixture data. The same query should
   return each user's permitted rows.
3. Copy [fixture.example.R](fixture.example.R) outside Git. Edit `backend`,
   `configure()`, and `validate()` for your data. The runner executes this file
   as trusted R code.
4. Set these variables privately:

| Variable | Value |
| --- | --- |
| `OAUTHDB_LIVE_A_TOKEN`, `OAUTHDB_LIVE_B_TOKEN` | Delegated user access tokens for the backend |
| `OAUTHDB_LIVE_A_EXPIRES_AT`, `OAUTHDB_LIVE_B_EXPIRES_AT` | Token expiry as Unix seconds, at least five minutes ahead |
| `OAUTHDB_LIVE_A_SCOPES`, `OAUTHDB_LIVE_B_SCOPES` | Actual granted scopes, separated by spaces |
| `OAUTHDB_LIVE_FIXTURE` | Path to the fixture R file |
| `OAUTHDB_LIVE_TESTS` | `true` |

Run from the repository root:

```sh
Rscript tests/integration/run-live.R
```

The summary reports pass or fail without printing tokens or query results.

## Before deploying an app

Use separate browser profiles for A and B and check that the same query returns
the right data for each. Then replace A with B in one session, refresh an
expired token, and sign out. Check that outputs follow the selected account
and stored results clear when access ends.

Test each service the app uses: Fabric SQL access, for example, does not
establish OneLake or semantic-model permissions. Confirm the query identity
in the platform's audit records. Record the client, driver, and platform
versions with the results.
