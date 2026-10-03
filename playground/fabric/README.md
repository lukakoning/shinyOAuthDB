# Fabric sandbox app

One app for Warehouse and Lakehouse SQL, DAX (JSON and Arrow), KQL, OneLake CSV
and Delta, mirrored Delta, paginated GraphQL, and workspace discovery. Native
fabricQueryR calls live in [queries.R](queries.R); [app.R](app.R) supplies Shiny
and the optional shinyOAuth sign-in. The app only reads data.

It defaults to the existing persistent `fabricqueryr-shiny-dhrkoning` workspace.
Discovery finds its seeded items by name; no endpoint or item IDs need copying.
Set `FABRIC_SHINY_WORKSPACE` to select another compatible sandbox.

## Start

Install shinyOAuthDB, the target-enabled shinyOAuth package, fabricQueryR 1.0.1
or later, and the drivers needed for the sources you want to try. Neither
fabricQueryR's Shiny helpers nor a modified token-provider API is required.
SQL defaults to odbc and Microsoft ODBC Driver 18; ADBC needs the MSSQL driver.
OneLake file/Delta and Arrow DAX need their normal fabricQueryR dependencies.

Use the existing guarded workflow in the fabricQueryR repository:

```sh
gh workflow run fabric-sandbox.yaml --repo KennispuntTwente/fabricQueryR --ref master -f sandbox=shiny -f action=start
```

Wait for setup to succeed, then run from this repository in R:

```r
# Load the sibling checkout if the installed fabricQueryR is older than 1.0.1.
pkgload::load_all("../fabricQueryR")
pkgload::load_all()
shiny::runApp("playground/fabric", port = 8100)
```

Open `http://localhost:8100/`. Choose a source and click **Load data**. After the
first load, changing the source or filters refreshes the result. DAX also plots
category totals. **Refresh discovered items** rechecks the workspace after setup
changes. Missing items or drivers affect their selected source only.

The workflow retains the workspace and arms its existing one-hour shutdown
before resuming F2. Finish early with `action=pause` in the same command. This
app does not start, seed, resize, or pause capacity.

## Authentication

`FABRIC_SHINY_AUTH` accepts `delegated`, `sandbox`, or `auto` (the default).

For visitor authorization, configure the existing `ENTRA_TENANT_ID`,
`ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET`, and `ENTRA_REDIRECT_URI` settings.
The corresponding `OAUTHDB_*` names also work. The callback defaults to
`http://localhost:8100/` and must be registered as a Web redirect URI.

The client preset requests the six configured services. Your registration needs
delegated permissions for Fabric workspace/item reads, SQL `user_impersonation`,
Power BI `Dataset.Read.All` and `GraphQLApi.Execute.All`, Kusto and Storage
`user_impersonation`, plus identity/refresh consent. Visitors still need the
appropriate workspace/item permissions, including Build on semantic models.
Configure your own native shinyOAuth client in `app.R` when your consent setup
differs, keeping the accessor's scopes and targets aligned.

In delegated mode, discovery and queries both use the signed-in visitor.
There is no fallback to the sandbox application if sign-in or a query fails.

For the existing shared sandbox connection, use `FABRICQUERYR_TENANT_ID`,
`FABRICQUERYR_CLIENT_ID`, and `FABRICQUERYR_CLIENT_SECRET`. These are the same
settings as fabricQueryR's playground. This mode uses the sandbox application
through AzureAuth and labels that identity in the UI; it does not demonstrate
visitor authorization. `auto` chooses delegated mode when any delegated
registration setting is present, otherwise sandbox mode.

## Check

The fixture's unfiltered data has three rows; the DAX models return two category
totals (A: 10.5, B: 20). SQL's minimum ID and DAX/KQL's category controls change
these results. GraphQL collects three rows across pages of two.

The read-only live runner uses the same discovery and query functions:

```sh
Rscript tools/check-fabric-sandbox.R
```

It uses shared sandbox credentials and records each source separately. Package
tests exercise the actual app with simulated A/B visitor grants, including
service routing, native arguments, failures, switching, and logout.
