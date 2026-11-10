test_that("HTTP array parameters ignore vector names and preserve object fields", {
  bodies <- list()
  httr2::local_mocked_responses(function(req) {
    bodies[[length(bodies) + 1L]] <<- jsonlite::parse_json(
      getFromNamespace("req_body_render", "httr2")(req)
    )
    if (grepl("crate.example", req$url, fixed = TRUE)) {
      odb_http_response('{"cols":[],"col_types":[],"rows":[],"rowcount":0}')
    } else {
      odb_http_response('{"Documents":[],"_count":0}')
    }
  })
  values <- list(
    c(first = 1L, second = 2L),
    c(first = "NL", second = "BE"),
    list(first = 1L, second = 2L),
    list(ids = c(first = 1L, second = 2L)),
    list(c(first = "NL", second = "BE"), list(active = TRUE))
  )
  expected <- list(
    list(1L, 2L),
    list("NL", "BE"),
    list(first = 1L, second = 2L),
    list(ids = list(1L, 2L)),
    list(list("NL", "BE"), list(active = TRUE))
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    crate <- oauth_db_cratedb_api(auth$connection, "https://crate.example/_sql")
    cosmos <- oauth_db_cosmos_api(
      auth$connection,
      "https://account.documents.azure.com",
      "reports",
      "orders",
      target = NULL
    )
    for (i in seq_along(values)) {
      crate$query("SELECT $1", parameters = list(values[[i]]))
      expect_identical(tail(bodies, 1L)[[1L]]$args[[1L]], expected[[i]])
      cosmos$query(
        "SELECT VALUE @value",
        parameters = list(value = values[[i]])
      )
      expect_identical(
        tail(bodies, 1L)[[1L]]$parameters[[1L]]$value,
        expected[[i]]
      )
    }
  })
})
