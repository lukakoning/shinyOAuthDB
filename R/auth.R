# Shared construction of native shinyOAuth clients.
.odb_oauth_client <- function(provider, client_id, redirect_uri, client_secret, scopes, ...) {
  .odb_string(client_id, "client_id")
  .odb_string(redirect_uri, "redirect_uri")
  if (is.null(client_secret) || identical(client_secret, "")) client_secret <- character()
  extras <- list(...)
  if (length(extras) && (is.null(names(extras)) || anyNA(names(extras)) ||
      any(!nzchar(names(extras))) || anyDuplicated(names(extras)))) {
    .odb_abort("Client settings in ... must have unique names.")
  }
  args <- list(provider = provider, client_id = client_id, client_secret = client_secret,
               redirect_uri = redirect_uri, scopes = scopes)
  do.call(shinyOAuth::oauth_client, c(args, extras))
}
