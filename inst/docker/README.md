# Local OAuth demos

From R, use `shinyOAuthDB::oauth_db_demo()` to run PostgreSQL, or choose
`"postgrest"`, `"trino"`, `"starrocks"`, `"duckdb"`, `"libsql"`, `"cratedb"`
or `"opensearch"`. Use `action = "files"` to copy
this directory without starting Docker.

Use `app = "local"` to start only the database and sign-in infrastructure
in Docker, and run the editable Shiny app in a local R process. Its copy
is at `local-app/<database>/app.R`. The extra `compose.local.yml` and
`<database>/compose.local.yml` files expose the database on host loopback
port 19444 and leave 18100 for local Shiny.

Use `demo <- oauth_db_demo("postgrest", action = "services")` to start the
infrastructure and continue running your own app in the same R session.
Use `demo$provider` and `demo$url` in the app, then call
`demo$stop()` when finished. `compose.services.yml` additionally exposes
Keycloak's HTTP endpoints on loopback port 18080 for R's OAuth requests.
The PostgREST override fetches signing keys with Python and exposes its API
over HTTP on loopback only, without building an R app image.

| File | Purpose |
| --- | --- |
| `compose.yml` | Shared Keycloak, certificates and Shiny runtime |
| `compose.<database>.yml` | The selected database and its dependencies |
| `compose.services.yml` | Loopback OAuth endpoints for services-only mode |
| `realm.json` | Demo accounts, app registration, token claims and audiences |
| `realm-extended.json` | Additional database clients, Ed25519 signing and database claims |
| `<database>/app.R` | The small Shiny app you can edit |
| `install.R` | Pinned R package sources used in the app containers |

[Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#build-a-small-app)
has passwords and cleanup; `?oauth_db_demo` describes the launcher options.
These configurations use public
test credentials and bind browser ports to loopback. Replace credentials
and certificates before adapting them for a deployment.
