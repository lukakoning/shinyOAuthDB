# Microsoft Fabric Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("fabric", path = ".")`.
`settings.dcf` stores non-secret settings; edit `app.R` to change SQL or
connection code and `demo-ui.R` to change the UI. Save and reload the browser.

Sign in, then click **Run example query**. The first query reports your
database identity without needing a table. Queries use your Fabric capacity.
Stopping the local app leaves that capacity and your cloud data alone.

A confidential app uses masked input or `OAUTHDB_FABRIC_CLIENT_SECRET`.
Keep secrets and tokens out of these files and source control.

See the [Fabric guide](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html)
for Entra registration, database permissions and API examples.

**Back to setup** opens a console menu of saved settings. Choose a setting
by number, `0` to continue, or `cancel` to save and return to R. Your other
settings and app edits are kept. Use a new empty `path` for fresh templates.
