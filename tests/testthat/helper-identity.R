odb_test_identity <- function(session) {
  skip_if_not_installed("jsonlite")
  provider <- shinyOAuth::oauth_provider_oidc(
    "identity-fixture",
    "https://login.example",
    token_auth_style = "public"
  )
  client <- shinyOAuth::oauth_client(
    provider,
    "identity-fixture",
    redirect_uri = "http://localhost:8100",
    state_key = openssl::rand_bytes(32),
    scopes = c("openid", "read")
  )
  auth <- odb_test_authorization(
    session,
    client = client,
    scopes = c("openid", "read")
  )
  auth$identity_token <- function(user = "alice") {
    encode <- function(value) {
      text <- as.character(jsonlite::toJSON(value, auto_unbox = TRUE))
      sub(
        "=+$",
        "",
        chartr("+/", "-_", openssl::base64_encode(charToRaw(text)))
      )
    }
    token <- auth$make_token(paste0("identity-", user))
    # Supply an already validated identity snapshot without an external issuer.
    token@id_token <- paste(
      encode(list(alg = "RS256")),
      encode(list(
        iss = provider@issuer,
        sub = "fixture-subject",
        preferred_username = user
      )),
      "c2lnbmF0dXJl",
      sep = "."
    )
    token@id_token_validated <- TRUE
    token
  }
  auth$token(auth$identity_token())
  auth$user <- function() {
    identity <- auth$connection$identity(claims = "preferred_username")
    shiny::req(identity$id_token_claims$preferred_username)
  }
  auth
}
