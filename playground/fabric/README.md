# Fabric sandbox app

Try Warehouse and Lakehouse SQL, DAX, KQL, OneLake files and Delta tables,
GraphQL, and workspace discovery in one Shiny app. The app reads prepared
data from the `fabricqueryr-shiny-dhrkoning` sandbox. Query code is in
[queries.R](queries.R); the Shiny app is in [app.R](app.R).

## Run

Install shinyOAuthDB, shinyOAuth 0.7.0 or later, and fabricQueryR 1.0.1 or
later. SQL uses odbc and Microsoft ODBC Driver 18 by default. Other sources
need their usual fabricQueryR dependencies.

Start the existing sandbox using its guarded workflow:

```sh
gh workflow run fabric-sandbox.yaml --repo KennispuntTwente/fabricQueryR --ref master -f sandbox=shiny -f action=start
```

Wait for setup to finish, then run from this repository:

```r
pkgload::load_all()
shiny::runApp("playground/fabric", port = 8100)
```

Open `http://localhost:8100/`, choose a source, and click **Load data**.
The app discovers items by name. Set `FABRIC_SHINY_WORKSPACE` to use another
compatible sandbox.

The workflow schedules a pause after one hour. To finish earlier, run the
same workflow command with `-f action=pause`. The app itself does not manage
capacity.

## Choose an identity

Set `FABRIC_SHINY_AUTH` to `delegated` for visitor sign-in or `sandbox` for
the shared test application. The default, `auto`, chooses delegated mode
when any delegated registration setting is present.

For visitor sign-in, set `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`,
`ENTRA_CLIENT_SECRET`, and `ENTRA_REDIRECT_URI`. The corresponding
`OAUTHDB_*` names also work. Register `http://localhost:8100/` as a Web
redirect URI, including the trailing slash.

This app uses Fabric, SQL, Power BI, Kusto, Storage, and GraphQL. The Entra
registration needs delegated permissions for all six, including
`Dataset.Read.All` and `GraphQLApi.Execute.All` for Power BI. Visitors also
need access to the workspace and items, including Build on semantic models.
See the [platform API guide](../../vignettes/platform-apis.Rmd) for service
selection.

For the shared sandbox identity, set `FABRICQUERYR_TENANT_ID`,
`FABRICQUERYR_CLIENT_ID`, and `FABRICQUERYR_CLIENT_SECRET`. The app labels
this identity in the UI. It uses AzureAuth and does not test visitor sign-in.
A failed visitor login or query never falls back to the shared identity.

## Live checks

After starting the sandbox, run:

```sh
Rscript tools/check-fabric-sandbox.R
Rscript tools/check-fabric-browser.R
```

These checks use the shared sandbox identity. Most sources return three
fixture rows; DAX returns two category totals, A: 10.5 and B: 20.
Package tests separately exercise visitor switching and sign-out with mocked
cloud calls.
