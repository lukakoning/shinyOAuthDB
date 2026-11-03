# PostgreSQL and Keycloak playground

Run a Shiny app against a local PostgreSQL 18 server with real OAuth sign-in.
The database enforces different rows and table permissions for Alice and Bob.

Install and start Docker with Linux containers, and check out
`lukakoning/shinyOAuth` next to this repository:

```text
GitHub/
  shinyOAuth/
  shinyOAuthDB/
```

From the shinyOAuthDB root:

```r
source("playground/postgres/run.R")
```

The launcher builds the images and starts the services. Once Shiny starts,
open `http://localhost:18100`; the Keycloak sign-in uses
`https://localhost:18443`. Your browser may ask you to trust the generated
local test certificate.

| Account | Password | Visible rows |
| --- | --- | --- |
| `alice` | `alice-fixture-password` | `alice-visible-1`, `alice-visible-2` |
| `bob` | `bob-fixture-password` | `bob-visible-1`, `bob-visible-2` |

Click **Authorize database user** and sign in. The table shows rows from
PostgreSQL; **Load granted rows** repeats the query. Try signing out and
switching accounts, refreshing the token, or probing the other role and
table grants. PostgreSQL rejects the unauthorized reads.

The app also exposes diagnostic controls used by the integration tests.
**Terminate fixture backend** breaks its database connection, and **Retry
held native connection** checks that the old handle cannot start another
OAuth flow. The JSON below the table contains test metadata and query
results, without access tokens.

Click **Stop playground** to close the app and remove its containers and
database volumes. Interrupting the launcher also attempts cleanup; if you
force its process to exit, run the cleanup command it printed at startup.
For faster
starts after a successful build, set `OAUTHDB_SKIP_BUILD=1`; unset it after
changing the Dockerfile. The runner installs your current package source
each time, including when the images are reused.

The same environment runs automatically through the
[PostgreSQL OAuth workflow](../../.github/workflows/postgres-integration.yaml).
Run it locally with the [integration runner](../../integration/postgres-keycloak/README.md).
For your own server, use the [standalone app](../example-postgres.R) and
[PostgreSQL guide](../../vignettes/postgres.Rmd).
