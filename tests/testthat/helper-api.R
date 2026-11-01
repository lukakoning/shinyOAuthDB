odb_test_fabric_authorization <- function(session, id = "A",
                                        services = c("fabric", "sql", "onelake", "dax", "graphql", "kql"),
                                        target_names = NULL, unacquired = character()) {
  targets <- .odb_microsoft_targets(services)
  if (!is.null(target_names)) names(targets) <- unname(target_names[names(targets)])
  default <- names(targets)[[1L]]
  client <- oauth_db_microsoft_client(client_id = "test", redirect_uri = "http://localhost:8100",
    provider = shinyOAuth::oauth_provider_microsoft(tenant = "organizations", userinfo_required = FALSE),
    token_targets = targets, token_target_default = default)
  make_token <- function(target, value = paste(id, target, sep = "-"),
                         scopes = targets[[target]]$scopes) {
    shinyOAuth::OAuthToken(access_token = value, token_type = "Bearer", refresh_token = "fixture-refresh",
      expires_at = as.numeric(Sys.time()) + 3600, granted_scopes = scopes,
      granted_scopes_verified = TRUE)
  }
  values <- stats::setNames(lapply(names(targets), function(target) {
    if (target %in% unacquired) NULL else make_token(target)
  }), names(targets))
  tokens <- shiny::reactiveVal(values)
  current <- shiny::reactiveVal(TRUE)
  calls <- new.env(parent = emptyenv())
  calls$targets <- character()
  connection <- getFromNamespace("OAuthConnection", "shinyOAuth")$new(
    id = id, client = client,
    resolve = function() {
      if (!current() || isTRUE(session$isClosed()) ||
          !identical(shiny::getDefaultReactiveDomain()$rootScope(), session$rootScope())) {
        getFromNamespace("connection_access_error", "shinyOAuth")("authorization_unavailable")
      }
      list(client = client, token = tokens()[[default]], status = "active",
           targets = list(tokens = tokens()))
    },
    acquire = function(async = FALSE, target = NULL, ...) {
      stopifnot(!async)
      if (is.null(target)) target <- default
      calls$targets <- c(calls$targets, target)
      values <- tokens()
      values[[target]] <- make_token(target, paste(id, target, length(calls$targets), sep = "-"))
      tokens(values)
      TRUE
    },
    is_current = function() current())
  list(connection = connection, tokens = tokens, current = current,
       calls = calls, make_token = make_token)
}
