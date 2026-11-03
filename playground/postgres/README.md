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

Click **Sign in** and choose either account. The table shows rows from
PostgreSQL; **Reload rows** repeats the query. **Switch account** opens a
new sign-in. Token refresh runs in background workers, with its progress
and result shown above the table. Controls become available when the
browser and the required authorization are ready.

Each permission check has a short result beneath its button. **Try the
other role** tests the database's identity mapping, **Check table access**
tries both private tables, and **Check token scope** asks PostgreSQL to
validate the current token. With the normal demo account, the scope check
succeeds because that token includes `database.read`.

The **Current session** fields show the account, granted scope and refresh
count. Expand **Connection details** for the backend process, connection
counts and authorization ID. Access tokens are never displayed.

Expand **Test connection recovery** to use **Break connection**, then
**Try the old connection** or **Reload rows**. The first failed read detects
the lost connection; the next reload opens a fresh one. The browser tests
use separate hidden metadata, so the full JSON does not fill the page.

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
