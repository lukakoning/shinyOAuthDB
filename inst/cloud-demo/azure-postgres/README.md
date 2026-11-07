# Your Azure PostgreSQL Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("azure-postgres", path = ".")`.
Edit `app.R` for SQL or connection settings and `demo-ui.R` for the UI.
Save and reload the browser. The first query needs no table; click
**Run example query** to connect and see your database role.

The server needs Entra authentication and a database principal mapped to
the user or their group. Each visitor signs in with their own account;
PostgreSQL verifies the requested role or group membership. Provide the
trusted CA bundle used to verify your server's TLS certificate.

A confidential app uses masked input or
`OAUTHDB_AZURE_POSTGRES_CLIENT_SECRET`. Keep secrets and tokens out of files.
Stopping the local demo leaves your Azure server under its own settings.
See the [Azure PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.html).
