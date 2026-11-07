live_apply_config <- function(
  encoded = Sys.getenv("OAUTHDB_LIVE_CONFIG_JSON")
) {
  if (!nzchar(encoded)) {
    return(invisible(NULL))
  }
  config <- jsonlite::fromJSON(encoded, simplifyVector = FALSE)
  if (
    !is.list(config) ||
      is.null(names(config)) ||
      anyDuplicated(names(config)) ||
      any(!grepl("^OAUTHDB_[A-Z][A-Z0-9_]*$", names(config))) ||
      any(grepl(
        "TOKEN|SECRET|PASSWORD|LIVE_TESTS|CREDENTIAL_MODE",
        names(config)
      )) ||
      !all(vapply(
        config,
        function(x) is.character(x) && length(x) == 1L && !is.na(x),
        logical(1)
      ))
  ) {
    stop(
      "Cloud configuration must contain named, non-secret OAUTHDB string settings.",
      call. = FALSE
    )
  }
  do.call(Sys.setenv, config)
  invisible(NULL)
}

live_google_refresh <- function(user) {
  if (!identical(Sys.getenv("OAUTHDB_LIVE_TESTS"), "true")) {
    stop("Live tests are disabled.", call. = FALSE)
  }
  prefix <- paste0("OAUTHDB_LIVE_", user, "_")
  required <- function(name) {
    value <- Sys.getenv(name)
    if (!nzchar(value)) {
      stop("Missing protected Google credential setting.", call. = FALSE)
    }
    value
  }
  scopes <- required(paste0(prefix, "SCOPES"))
  issued <- as.numeric(Sys.time())
  response <- tryCatch(
    {
      httr2::request("https://oauth2.googleapis.com/token") |>
        httr2::req_body_form(
          grant_type = "refresh_token",
          refresh_token = required(paste0(prefix, "REFRESH_TOKEN")),
          client_id = required("OAUTHDB_CLIENT_ID"),
          client_secret = required("OAUTHDB_CLIENT_SECRET")
        ) |>
        httr2::req_options(followlocation = FALSE) |>
        httr2::req_timeout(30) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
    },
    error = function(e) {
      stop(
        "Google delegated credential renewal failed; review protected environment credentials.",
        call. = FALSE
      )
    }
  )
  if (
    !is.list(response) ||
      !is.character(response$access_token) ||
      length(response$access_token) != 1L ||
      is.na(response$access_token) ||
      !grepl("^[A-Za-z0-9._~+/-]+=*$", response$access_token) ||
      !is.numeric(response$expires_in) ||
      length(response$expires_in) != 1L ||
      !is.finite(response$expires_in) ||
      response$expires_in <= 300 ||
      !identical(tolower(response$token_type), "bearer")
  ) {
    stop(
      "Google renewal did not return a usable delegated bearer and lifetime.",
      call. = FALSE
    )
  }
  if (!is.null(response$scope)) {
    if (
      !is.character(response$scope) ||
        length(response$scope) != 1L ||
        is.na(response$scope)
    ) {
      stop(
        "Google renewal returned invalid permission evidence.",
        call. = FALSE
      )
    }
    scopes <- response$scope
  }
  values <- stats::setNames(
    list(
      response$access_token,
      as.character(issued + response$expires_in),
      scopes
    ),
    paste0(prefix, c("TOKEN", "EXPIRES_AT", "SCOPES"))
  )
  do.call(Sys.setenv, values)
  invisible(NULL)
}
