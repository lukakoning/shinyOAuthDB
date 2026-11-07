# Amazon Redshift Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("redshift", path = ".")`.
This example signs users in through Microsoft Entra and presents the external
JWT to Redshift's `IdpTokenAuthPlugin`. The deployment must already have
IAM Identity Center trusted-token integration and database permissions.

If setup is pending, resume with `identity_center_ready = "yes"` after your
administrator configures it. The Entra resource and delegated scope must
match that deployment's accepted token configuration.

Edit `app.R` for SQL and connection code, or `demo-ui.R` for the UI; save and
reload. The identity query runs only after **Run example query**. Stopping
the app does not pause a cluster or stop cloud charges.
A confidential app uses masked input or `OAUTHDB_REDSHIFT_CLIENT_SECRET`.
Keep secrets and tokens out of these files.
See the [Redshift guide](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html).

**Back to setup** opens a console menu of saved settings. Choose a setting
by number, `0` to continue, or `cancel` to save and return to R. Your other
settings and app edits are kept. Use a new empty `path` for fresh templates.
