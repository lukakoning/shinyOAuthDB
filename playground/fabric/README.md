# Fabric sandbox app

Use this app to query the prepared Fabric sandbox and try different data
sources. It includes Warehouse and Lakehouse SQL, DAX, KQL, OneLake files
and tables, GraphQL, and workspace discovery.

The default workspace is `fabricqueryr-shiny-dhrkoning`. The queries are
in [queries.R](queries.R), and the app is in [app.R](app.R).

## Run

Install shinyOAuthDB, shinyOAuth 0.7.0 or later, and fabricQueryR 1.0.1 or
later. SQL uses odbc and Microsoft ODBC Driver 18 by default. Other sources
need their usual fabricQueryR dependencies.

Start the existing sandbox with its workflow:

```sh
gh workflow run fabric-sandbox.yaml --repo KennispuntTwente/fabricQueryR --ref master -f sandbox=shiny -f action=start
```

Wait for setup to finish, then run from this repository:

```r
pkgload::load_all()
shiny::runApp("playground/fabric", port = 8100)
```

Open `http://localhost:8100/`, choose a source, and click **Load data**.
The app finds items by name. Set `FABRIC_SHINY_WORKSPACE` to use another
sandbox with the same prepared data.

The workflow schedules a pause after one hour. To pause it earlier, run
the workflow command with `-f action=pause`.

## Choose how to sign in

Use `FABRIC_SHINY_AUTH=delegated` to sign visitors in with their own
accounts. Use `sandbox` for the shared test application. The default,
`auto`, selects visitor sign-in when any of its registration settings
are present.

For visitor sign-in, set `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`,
`ENTRA_CLIENT_SECRET`, and `ENTRA_REDIRECT_URI`. The corresponding
`OAUTHDB_*` names also work. Register `http://localhost:8100/` as a Web
redirect URI, including the trailing slash.

This app uses Fabric, SQL, Power BI, Kusto, Storage, and GraphQL. The Entra
registration needs delegated permissions for all six, including
`Dataset.Read.All` and `GraphQLApi.Execute.All` for Power BI. Visitors also
need access to the workspace and items, including Build on semantic models.
The [Fabric guide](../../vignettes/fabric.Rmd#choose-additional-services)
explains the service settings.

For the shared sandbox account, set `FABRICQUERYR_TENANT_ID`,
`FABRICQUERYR_CLIENT_ID`, and `FABRICQUERYR_CLIENT_SECRET`. The app shows
which account it uses. Shared mode uses AzureAuth; a failed visitor login
or query doesn't switch to it.

## Live checks

After starting the sandbox, run:

```sh
Rscript tools/check-fabric-sandbox.R
Rscript tools/check-fabric-browser.R
```

These checks use the shared sandbox account. Most sources return three
test rows; DAX returns category totals of 10.5 for A and 20 for B.
Package tests check account switching and sign-out with mocked services.
