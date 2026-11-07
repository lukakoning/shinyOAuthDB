test_that("warehouse discovery follows pages using the visitor's current authorization", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "sql")
    api <- oauth_db_databricks_api(
      auth$connection,
      "workspace.example",
      required_scopes = "sql"
    )
    requests <- list()
    httr2::local_mocked_responses(function(req) {
      requests[[length(requests) + 1L]] <<- req
      if (length(requests) == 1L) {
        odb_http_response(
          '{"warehouses":[{"id":"a","name":"Reporting","state":"RUNNING"}],"next_page_token":"page-2"}'
        )
      } else {
        odb_http_response(
          '{"warehouses":[{"id":"b","name":"Analytics","state":"STOPPED"}]}'
        )
      }
    })
    rows <- api$warehouses()
    expect_identical(rows$id, c("a", "b"))
    expect_identical(rows$state, c("RUNNING", "STOPPED"))
    expect_match(requests[[2L]]$url, "page_token=page-2", fixed = TRUE)
    expect_true(all(vapply(
      requests,
      function(req) httr2::req_get_method(req) == "GET",
      logical(1)
    )))
    expect_true(all(vapply(
      requests,
      function(req) !isTRUE(req$options$followlocation),
      logical(1)
    )))
    expect_identical(
      httr2::req_get_headers(requests[[1L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A"
    )
    auth$current(FALSE)
    expect_error(api$warehouses(), class = "shiny.silent.error")
    expect_length(requests, 2L)
  })
})

test_that("warehouse discovery discards stale responses and rejects broken pagination", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "sql")
    api <- oauth_db_databricks_api(auth$connection, "workspace.example")
    httr2::local_mocked_responses(function(req) {
      auth$current(FALSE)
      odb_http_response(
        '{"warehouses":[{"id":"a","name":"Private","state":"RUNNING"}]}'
      )
    })
    expect_error(
      api$warehouses(),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "sql")
    api <- oauth_db_databricks_api(auth$connection, "workspace.example")
    httr2::local_mocked_responses(function(req) {
      odb_http_response('{"warehouses":[],"next_page_token":"cycle"}')
    })
    expect_error(
      api$warehouses(),
      "pagination",
      class = "shinyOAuthDB_invalid_response"
    )
  })
})

test_that("warehouse HTTP and shape errors are safe and empty results are typed", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "sql")
    api <- oauth_db_databricks_api(auth$connection, "workspace.example")
    httr2::local_mocked_responses(function(req) {
      odb_http_response('{"error":"Bearer secret echoed"}', 403L)
    })
    error <- expect_error(
      api$warehouses(),
      class = "shinyOAuthDB_request_failed"
    )
    expect_identical(error$status, 403L)
    expect_false(grepl("secret echoed", conditionMessage(error), fixed = TRUE))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "sql")
    api <- oauth_db_databricks_api(auth$connection, "workspace.example")
    httr2::local_mocked_responses(function(req) odb_http_response('{}'))
    expect_identical(
      api$warehouses(),
      data.frame(id = character(), name = character(), state = character())
    )
  })
})
