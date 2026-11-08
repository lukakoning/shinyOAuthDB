supabase_legacy_key <- function(claims = list(role = "anon")) {
  encode <- function(value) {
    text <- jsonlite::toJSON(value, auto_unbox = TRUE)
    sub(
      "=+$",
      "",
      chartr("+/", "-_", as.character(openssl::base64_encode(text)))
    )
  }
  paste(
    encode(list(alg = "HS256", typ = "JWT")),
    encode(claims),
    "signature",
    sep = "."
  )
}

test_that("Supabase separates the project key from each visitor's bearer token", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response('[{"id":9007199254740993,"note":"visitor row"}]')
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <- shiny::reactiveVal(NULL)
    api <- oauth_db_supabase_api(
      selected,
      "https://project.example/proxy/",
      "sb_publishable_fixture",
      schema = "reports",
      ca_bundle = "ca.pem"
    )
    expect_s3_class(api, "OAuthSupabaseAPI")
    expect_s3_class(api, "OAuthPostgRESTAPI")
    expect_error(api$select("notes"), class = "shiny.silent.error")
    expect_length(requests, 0L)
    selected(auth$connection)
    rows <- api$select(
      "notes",
      filters = list(note = "eq.visitor row"),
      limit = 2L
    )
    expect_identical(rows$id, "9007199254740993")
    auth$token(auth$make_token("renewed-user-token"))
    api$select("notes")
    expect_output(print(api), "^<OAuthSupabaseAPI>")
    selected(NULL)
    expect_error(api$select("notes"), class = "shiny.silent.error")
  })
  expect_length(requests, 2L)
  expect_match(
    requests[[1L]]$url,
    "https://project.example/proxy/rest/v1/notes?",
    fixed = TRUE
  )
  expect_identical(httr2::url_parse(requests[[1L]]$url)$query$limit, "2")
  headers <- lapply(requests, httr2::req_get_headers, redacted = "reveal")
  expect_identical(
    vapply(headers, `[[`, "", "apikey"),
    rep("sb_publishable_fixture", 2L)
  )
  expect_identical(
    vapply(headers, `[[`, "", "Authorization"),
    c("Bearer fixture-A", "Bearer renewed-user-token")
  )
  expect_identical(headers[[1L]][["Accept-Profile"]], "reports")
  expect_identical(requests[[1L]]$options$cainfo, "ca.pem")
  expect_false(requests[[1L]]$options$followlocation)
})

test_that("Supabase preserves the project key on read refresh and never replays writes", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 2L) {
      odb_http_response("[]")
    } else {
      odb_http_response("private", 401L)
    }
  })
  key <- supabase_legacy_key()
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_supabase_api(
      auth$connection,
      "https://project.example",
      key
    )
    expect_identical(api$select("notes"), data.frame())
    expect_identical(auth$calls$acquire, 1L)
    for (method in c("POST", "PATCH", "PUT", "DELETE")) {
      expect_error(
        api$request("notes", method = method),
        class = "shinyOAuthDB_request_failed"
      )
    }
    expect_error(api$rpc("note_total"), class = "shinyOAuthDB_request_failed")
    expect_identical(auth$calls$acquire, 1L)
  })
  expect_length(requests, 7L)
  for (req in requests) {
    expect_identical(
      httr2::req_get_headers(req, redacted = "reveal")$apikey,
      key
    )
  }
  expect_identical(
    httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
    "Bearer fixture-A-acquired"
  )
})

test_that("Supabase RPCs, writes and HEAD keep native PostgREST behavior", {
  requests <- list()
  payload <- "3"
  status <- 200L
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(payload, status, list("Content-Range" = "0-1/2"))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_supabase_api(
      auth$connection,
      "https://project.example",
      "sb_publishable_fixture",
      schema = "reports"
    )
    expect_equal(api$rpc("add_them", list(a = 1L, b = 2L)), 3)
    payload <<- ""
    status <<- 204L
    expect_null(api$request(
      "notes",
      method = "PATCH",
      body = list(note = "updated")
    ))
    response <- api$request("notes", method = "HEAD")
    expect_s3_class(response, "httr2_response")
    expect_identical(httr2::resp_header(response, "Content-Range"), "0-1/2")
  })
  expect_match(requests[[1L]]$url, "/rest/v1/rpc/add_them$", perl = TRUE)
  expect_identical(
    requests[[1L]]$body$data,
    list(a = 1L, b = 2L)
  )
  expect_identical(
    httr2::req_get_headers(requests[[1L]], redacted = "reveal")[[
      "Content-Profile"
    ]],
    "reports"
  )
  expect_identical(
    httr2::req_get_headers(requests[[3L]], redacted = "reveal")[[
      "Accept-Profile"
    ]],
    "reports"
  )
})

test_that("Supabase clients isolate accounts and discard results after authorization changes", {
  selected <- NULL
  replacement <- NULL
  change_account <- FALSE
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (change_account) {
      selected(replacement)
    }
    odb_http_response('[{"note":"private row"}]')
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A", scopes = "read")
    b <- odb_test_authorization(session, id = "B", scopes = "read")
    selected <<- shiny::reactiveVal(a$connection)
    api <- oauth_db_supabase_api(
      selected,
      "https://project.example",
      "sb_publishable_fixture",
      required_scopes = "read"
    )
    expect_identical(api$select("notes")$note, "private row")
    replacement <<- b$connection
    change_account <<- TRUE
    expect_error(
      api$select("notes"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    change_account <<- FALSE
    api$select("notes")
    b$token(b$make_token("permission-lost", character()))
    expect_error(api$select("notes"), class = "shiny.silent.error")
    retained <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      retained$select("notes"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
  expect_length(requests, 3L)
  expect_identical(
    httr2::req_get_headers(requests[[3L]], redacted = "reveal")$Authorization,
    "Bearer fixture-B"
  )
})

test_that("Supabase project keys stay with their client and HTTP failures omit credentials", {
  requests <- list()
  fail <- FALSE
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (fail) {
      odb_http_response(
        '{"code":"42501","message":"sb_publishable_first fixture-A private-row"}',
        403L
      )
    } else {
      odb_http_response("[]")
    }
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    first <- oauth_db_supabase_api(
      auth$connection,
      "https://first.example",
      "sb_publishable_first"
    )
    second <- oauth_db_supabase_api(
      auth$connection,
      "https://second.example",
      "sb_publishable_second+/=."
    )
    plain <- oauth_db_postgrest_api(auth$connection, "https://plain.example")
    first$select("notes")
    second$select("notes")
    plain$select("notes")
    fail <<- TRUE
    error <- expect_error(
      first$select("notes"),
      class = "shinyOAuthDB_request_failed"
    )
    expect_identical(error$status, 403L)
    expect_identical(error$service_code, "42501")
    expect_false(grepl(
      "sb_publishable|fixture-A|private-row",
      conditionMessage(error)
    ))
    expect_null(error$parent)
    expect_null(error$resp)
    expect_null(error[["request"]])
  })
  expect_length(requests, 4L)
  headers <- lapply(requests, httr2::req_get_headers, redacted = "reveal")
  expect_identical(headers[[1L]]$apikey, "sb_publishable_first")
  expect_identical(headers[[2L]]$apikey, "sb_publishable_second+/=.")
  expect_null(headers[[3L]]$apikey)
  expect_identical(headers[[4L]]$apikey, "sb_publishable_first")
})

test_that("Supabase rejects elevated or malformed project keys before authorization", {
  invalid <- list(
    NULL,
    NA_character_,
    "",
    character(),
    c("one", "two"),
    TRUE,
    "sb_secret_private-canary",
    "sb_publishable_",
    "sb_publishable_key\r\nHost: other",
    "unknown-project-key",
    "e30.bm90LWpzb24.signature",
    "e30.WyJhbm9uIl0.signature",
    supabase_legacy_key(list(role = "service_role")),
    supabase_legacy_key(list(role = "authenticated")),
    supabase_legacy_key(list(role = list("anon"))),
    supabase_legacy_key(list(iss = "supabase"))
  )
  for (key in invalid) {
    error <- expect_error(
      oauth_db_supabase_api(
        stop("Authorization must stay lazy"),
        "https://project.example",
        key
      ),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_false(grepl("private-canary", conditionMessage(error), fixed = TRUE))
    expect_null(error$parent)
  }
})

test_that("Supabase accepts only project base URLs over HTTPS", {
  for (url in c(
    "http://project.example",
    "https://user:password@project.example",
    "https://project.example?apikey=secret",
    "https://project.example/#fragment",
    "https://project.example/../other",
    "https://project.example/%2e%2e/other",
    "https://project.example/rest/v1",
    "https://project.example/auth/v1/"
  )) {
    expect_error(
      oauth_db_supabase_api(
        stop("Authorization must stay lazy"),
        url,
        "sb_publishable_fixture"
      ),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
})

test_that("Supabase discovers native OAuth endpoints and configures public and confidential clients", {
  requests <- list()
  issuer <- "https://project.example/auth/v1"
  metadata <- list(
    issuer = issuer,
    authorization_endpoint = paste0(issuer, "/oauth/authorize"),
    token_endpoint = paste0(issuer, "/oauth/token"),
    userinfo_endpoint = paste0(issuer, "/oauth/userinfo"),
    jwks_uri = paste0(issuer, "/.well-known/jwks.json"),
    response_types_supported = list("code"),
    subject_types_supported = list("public"),
    grant_types_supported = list("authorization_code", "refresh_token"),
    id_token_signing_alg_values_supported = list("ES256", "RS256"),
    scopes_supported = list("openid", "profile", "email", "phone"),
    code_challenge_methods_supported = list("S256"),
    token_endpoint_auth_methods_supported = list(
      "client_secret_basic",
      "client_secret_post",
      "none"
    )
  )
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(jsonlite::toJSON(metadata, auto_unbox = TRUE))
  })
  for (secret in list(NULL, "", "client-secret")) {
    client <- oauth_db_supabase_client(
      "https://project.example/",
      "app",
      "http://localhost:8100",
      client_secret = secret
    )
    expect_s3_class(client, "shinyOAuth::OAuthClient")
    expect_identical(client@scopes, c("openid", "profile", "email"))
    expect_identical(client@provider@issuer, issuer)
    expect_identical(client@provider@auth_url, metadata$authorization_endpoint)
    expect_identical(client@provider@token_url, metadata$token_endpoint)
    expect_identical(client@provider@jwks_uri, metadata$jwks_uri)
    expect_identical(
      client@provider@token_auth_style,
      if (identical(secret, "client-secret")) "header" else "public"
    )
    expect_true(client@provider@use_pkce)
    expect_true(client@provider@use_nonce)
    expect_true(client@provider@id_token_validation)
    expect_false(client@provider@userinfo_required)
  }
  expect_identical(
    requests[[1L]]$url,
    paste0(issuer, "/.well-known/openid-configuration")
  )
})

test_that("Supabase accepts a project's third-party provider without discovering Supabase Auth", {
  provider <- shinyOAuth::oauth_provider(
    "external",
    "https://issuer.example/authorize",
    "https://issuer.example/token",
    token_auth_style = "public"
  )
  client <- oauth_db_supabase_client(
    url = stop("Do not evaluate replaced defaults"),
    client_id = "app",
    redirect_uri = "http://localhost:8100",
    provider = provider,
    scopes = "read",
    required_scopes = "read",
    label = "Reporting"
  )
  expect_identical(client@provider, provider)
  expect_identical(client@scopes, "read")
  expect_identical(client@required_scopes, "read")
  expect_identical(client@label, "Reporting")
})
