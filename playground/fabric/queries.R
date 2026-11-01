# fabricQueryR queries for the prepared Fabric sandbox.
fabric_demo_sources <- c(
  "Warehouse / SQL" = "warehouse", "Lakehouse / SQL" = "lakehouse",
  "Semantic model / DAX" = "dax", "Semantic model / DAX / Arrow" = "dax_arrow",
  "Eventhouse / KQL" = "kql", "OneLake / CSV" = "files",
  "OneLake / Delta" = "delta", "Mirrored database / Delta" = "mirrored",
  "GraphQL / paginated" = "graphql", "Workspace / discovery" = "discovery"
)
fabric_demo_discover <- function(token, workspace_name) {
  workspaces <- fabricQueryR::fabric_workspaces(token = token)
  matches <- Filter(function(x) identical(x[["displayName"]], workspace_name), workspaces)
  if (length(matches) != 1L) stop("Expected one accessible workspace named ", workspace_name, ".")
  workspace <- matches[[1L]]
  items <- fabricQueryR::fabric_items(workspace, detail = TRUE, detail_errors = "record", token = token)
  list(workspace = workspace, items = items)
}

fabric_demo_item <- function(sandbox, name, type) {
  matches <- Filter(function(x) identical(x[["displayName"]], name) &&
    identical(x[["type"]], type), sandbox$items)
  if (length(matches) != 1L) stop("The sandbox is missing ", name, " (", type, ").")
  matches[[1L]]
}

fabric_demo_read <- function(source, sandbox, token, min_id = 1L,
                             category = "All", backend = "odbc", shared = FALSE) {
  item <- function(name, type) fabric_demo_item(sandbox, name, type)
  switch(source,
    warehouse = , lakehouse = {
      target <- if (source == "warehouse") item("TestWarehouse", "Warehouse") else item("TestLakehouse", "Lakehouse")
      table <- if (source == "warehouse") "fabricqueryr_sql_types" else "fabricqueryr_basic"
      # fabric_sql_query() opens/closes a native ODBC or ADBC connection.
      fabricQueryR::fabric_sql_query(target,
        sql = paste0("SELECT id, name, amount FROM dbo.", table, " WHERE id >= ? ORDER BY id"),
        params = list(as.integer(min_id)), backend = backend, numeric_policy = "driver",
        token = token, read_only = TRUE, verbose = FALSE)
    },
    dax = , dax_arrow = {
      target <- item(if (source == "dax") "FabricQueryRIntegrationModel" else "FabricQueryRArrowIntegrationModel", "SemanticModel")
      stopifnot(category %in% c("All", "A", "B"))
      filter <- if (category == "All") "" else paste0('TREATAS({"', category, '"}, \'Facts\'[category]), ')
      result <- fabricQueryR::fabric_pbi_dax_query(target,
        dax = paste0("EVALUATE SUMMARIZECOLUMNS('Facts'[category], ", filter,
          '\"Rows\", COUNTROWS(\'Facts\'), \"Amount\", SUM(\'Facts\'[amount])) ORDER BY \'Facts\'[category]'),
        api = if (source == "dax") "json" else "arrow", token = token)
      names(result) <- c("Category", "Rows", "Amount")
      result
    },
    kql = fabricQueryR::fabric_kql_query(item("TestKQLDatabase", "KQLDatabase"),
      query = paste("declare query_parameters(selected_category:string);",
        "fabricqueryr_events | where selected_category == 'All' or category == selected_category",
        "| project id, name, category, amount | order by id asc"),
      parameters = list(selected_category = category), token = token),
    files = fabricQueryR::fabric_onelake_read_file(sandbox$workspace,
      item("TestLakehouse", "Lakehouse"), path = "Files/fixtures/basic.csv", token = token),
    delta = fabricQueryR::fabric_lakehouse_read_table(item("TestLakehouse", "Lakehouse"),
      "fabricqueryr_basic", schema = "dbo", columns = c("id", "name", "category", "amount"),
      limit = 100L, token = token, verbose = FALSE),
    mirrored = fabricQueryR::fabric_mirrored_database_read_table(
      item("TestMirroredDatabase", "MirroredDatabase"), "fabricqueryr_mirror_types",
      schema = "dbo", columns = c("id", "name", "amount"), limit = 100L, token = token, verbose = FALSE),
    graphql = {
      pages <- fabricQueryR::fabric_graphql_paginate(item("TestGraphQL", "GraphQLApi"),
        query = paste("query Paged($first: Int!, $after: String) {",
          "fabricqueryr_basics(first: $first, after: $after, orderBy: {id: ASC}) {",
          "items { id name category amount } hasNextPage endCursor } }"),
        variables = list(first = 2L, after = NULL), operation_name = "Paged",
        next_cursor = fabricQueryR::fabric_graphql_cursor("fabricqueryr_basics"),
        error_policy = "error", token = token,
        audience = if (shared) "https://api.fabric.microsoft.com/.default" else
          "https://analysis.windows.net/powerbi/api/GraphQLApi.Execute.All")
      fabricQueryR::fabric_graphql_collect(pages, c("fabricqueryr_basics", "items"))
    },
    discovery = data.frame(
      Name = vapply(sandbox$items, function(x) x[["displayName"]], character(1)),
      Type = vapply(sandbox$items, function(x) x[["type"]], character(1))),
    stop("Unknown data source.")
  )
}

# Optional shared sandbox mode: the existing sandbox app registration, not a
# visitor authorization. This example-only callback uses AzureAuth directly.
fabric_demo_shared_token <- function() {
  settings <- Sys.getenv(c("FABRICQUERYR_TENANT_ID", "FABRICQUERYR_CLIENT_ID", "FABRICQUERYR_CLIENT_SECRET"))
  if (any(!nzchar(settings))) stop("Set all three FABRICQUERYR_* sandbox credentials or configure delegated sign-in.")
  cache <- new.env(parent = emptyenv())
  function(audience, force_refresh = FALSE) {
    token <- cache[[audience]]
    if (is.null(token)) {
      token <- AzureAuth::get_azure_token(resource = audience, tenant = settings[[1L]],
        app = settings[[2L]], password = settings[[3L]], auth_type = "client_credentials", version = 2)
      cache[[audience]] <- token
    } else if (force_refresh || !token$validate()) token$refresh()
    token$credentials$access_token
  }
}
