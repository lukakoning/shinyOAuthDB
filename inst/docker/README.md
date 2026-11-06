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

| File | Purpose |
| --- | --- |
| `compose.yml` | Shared Keycloak, certificates and Shiny runtime |
| `compose.<database>.yml` | The selected database and its dependencies |
| `realm.json` | Demo accounts, app registration, token claims and audiences |
| `realm-extended.json` | Additional database clients, Ed25519 signing and database claims |
| `<database>/app.R` | The small Shiny app you can edit |
| `install.R` | Pinned R package sources used in the app containers |

The [demo guide](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html)
has passwords, cleanup and troubleshooting. These configurations use public
test credentials and bind browser ports to loopback. Replace credentials
and certificates before adapting them for a deployment.
