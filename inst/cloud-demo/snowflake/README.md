# Your Snowflake Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("snowflake", path = ".")`.
Edit `app.R` to change the SQL or connection settings and `demo-ui.R` for the
UI. Save and reload the browser. Settings contain no credentials.

Sign in and click **Run example query** to see your Snowflake user and role.
Your OAuth role and connection role must match. Queries may resume a
warehouse and consume credits; stopping the app doesn't suspend it.

Use the masked prompt or `OAUTHDB_SNOWFLAKE_CLIENT_SECRET` for the custom
OAuth integration's secret. Keep secrets and tokens out of these files.
The [Snowflake guide](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.html)
contains registration SQL, driver instructions and role/warehouse grants.
