# Google BigQuery Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("bigquery", path = ".")`.
Edit `app.R` to change SQL or connection code and `demo-ui.R` for the UI.
Save and reload the browser. `settings.dcf` stores non-secret configuration.

Use your Google account to sign in, then click **Run example query**.
The first query reports your identity and needs no table. Queries create
jobs in the configured project; the example sets a maximum bytes billed
limit. Match the location to your datasets before querying them.
Stopping the app does not cancel a submitted job.

Enter the Web OAuth client's secret through the masked guide or
`OAUTHDB_BIGQUERY_CLIENT_SECRET`. Keep secrets and tokens out of these files.
The [BigQuery guide](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.html)
explains Web OAuth registration, consent test users and IAM permissions.

**Back to setup** opens a console menu of saved settings. Choose a setting
by number, `0` to continue, or `cancel` to save and return to R. Your other
settings and app edits are kept. Use a new empty `path` for fresh templates.
