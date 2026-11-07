# Databricks Shiny demo

Run `shinyOAuthDB::oauth_db_cloud_demo("databricks", path = ".")` from this
directory to resume. `settings.dcf` contains non-secret settings. Edit
`app.R`, save and reload the browser to try a different query or UI.

For a confidential OAuth registration, provide its secret through the
masked guide or `OAUTHDB_DATABRICKS_CLIENT_SECRET`. Keep secrets out of
these files and source control.

Sign in in the browser, choose a SQL warehouse and click **Run example
query**. The first query reports your database identity without needing
a table. Running SQL can start a stopped warehouse and use compute credits.
Stopping this local app doesn't stop or change your shared warehouse.

The [cloud demo guide](https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.html)
explains registration, Free Edition limits and common setup problems.

**Back to setup** opens a console menu of saved settings. Choose a setting
by number, `0` to continue, or `cancel` to save and return to R. Your other
settings and app edits are kept. Use a new empty `path` for fresh templates.
