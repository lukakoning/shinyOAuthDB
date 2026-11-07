# Your Azure SQL Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("azure-sql", path = ".")`.
Edit `app.R` for SQL and connection settings, or `demo-ui.R` for the UI;
save and reload the browser. Settings contain no credentials.

Sign in with your Microsoft account, then click **Run example query**.
Azure SQL must have Entra authentication enabled, a database principal
for you or your group, and network access from this computer. OAuth consent
alone does not create a database user or grant data permissions.

A confidential registration uses masked input or
`OAUTHDB_AZURE_SQL_CLIENT_SECRET`. Keep secrets out of these files.
Stopping the app leaves your Azure database running under its own settings.
See the [Azure SQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html).

**Back to setup** opens a console menu of saved settings. Choose a setting
by number, `0` to continue, or `cancel` to save and return to R. Your other
settings and app edits are kept. Use a new empty `path` for fresh templates.
