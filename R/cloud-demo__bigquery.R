.odb_cloud_spec_bigquery <- function() {
  list(
    title = "Google BigQuery",
    purpose = "Run GoogleSQL as the person who signs in with Google. The first query shows your database identity and needs no dataset or table.",
    account_url = "https://docs.cloud.google.com/bigquery/docs/sandbox",
    setup_url = "https://docs.cloud.google.com/bigquery/docs/access-control",
    registration_url = "https://developers.google.com/identity/protocols/oauth2/web-server",
    registration = c(
      "In Google Cloud Console, choose a project and enable the BigQuery API. In Google Auth Platform configure Branding and Audience; add your Google account as a test user while the app is in Testing.",
      "Under Clients, create a Web application OAuth client and register the local callback shown below. Copy Client ID; enter its client secret only through the masked prompt or OAUTHDB_BIGQUERY_CLIENT_SECRET.",
      "Allow the https://www.googleapis.com/auth/bigquery scope. The signed-in user needs BigQuery Job User on the query project, and Data Viewer or equivalent access for tables they read. OAuth consent does not grant these IAM roles.",
      "The BigQuery sandbox is a no-billing starting point for supported queries, but you still need a project, API access and your own Web OAuth registration. Organization policies and sandbox limits apply."
    ),
    cost = "Queries create jobs in your selected project. The example sets a maximum bytes billed limit; editing SQL can use your query allowance. Stopping the app does not cancel a submitted job.",
    client_types = "confidential",
    packages = list(jsonlite = NULL),
    required = c("project", "client_id"),
    fields = list(
      project = .odb_cloud_field(
        "Choose the query project",
        "In Google Cloud Console's project selector, copy the project ID, not the display name or project number. Query jobs and any charges belong to this project.",
        "project"
      ),
      location = .odb_cloud_field(
        "BigQuery location",
        "The identity query uses US by default. Before querying your tables, copy their dataset location from BigQuery Explorer > dataset > Details, and supply location when resuming.",
        default = "US"
      ),
      maximum_bytes_billed = .odb_cloud_field(
        "Query byte limit",
        "Maximum bytes a query may bill. LIMIT on returned rows does not provide the same protection. Supply an integer string to change this limit.",
        "bytes",
        "10000000"
      )
    )
  )
}
