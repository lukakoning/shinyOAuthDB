# Local OAuth demos

From R, use `shinyOAuthDB::oauth_db_demo()` to run PostgreSQL, or choose
`"postgrest"`, `"trino"` or `"starrocks"`. Use `action = "files"` to copy
this directory without starting Docker.

| File | Purpose |
| --- | --- |
| `compose.yml` | Shared Keycloak, certificates and Shiny runtime |
| `compose.<database>.yml` | The selected database and its dependencies |
| `realm.json` | Demo accounts, app registration, token claims and audiences |
| `<database>/app.R` | The small Shiny app you can edit |
| `install.R` | Pinned R package sources used in the app containers |

The [demo guide](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html)
has passwords, cleanup and troubleshooting. These configurations use public
test credentials and bind browser ports to loopback. Replace credentials
and certificates before adapting them for a deployment.
