salesforce_fixture <- function(
  data = list(list("visible")),
  finished = TRUE,
  count = length(data),
  id = "query%2Fone"
) {
  list(
    returnedRows = length(data),
    metadata = list(list(name = "name", type = "varchar")),
    data = data,
    status = list(
      queryId = id,
      completionStatus = if (finished) "Finished" else "Running",
      rowCount = count
    )
  )
}

salesforce_response <- function(body, status = 200L) {
  odb_http_response(
    jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"),
    status
  )
}

test_that("Salesforce sign-in discovers the configured issuer and requests user consent", {
  issuer <- NULL
  provider <- shinyOAuth::oauth_provider(
    name = "salesforce",
    issuer = "https://login.salesforce.com",
    auth_url = "https://login.salesforce.com/services/oauth2/authorize",
    token_url = "https://login.salesforce.com/services/oauth2/token",
    jwks_uri = "https://login.salesforce.com/id/keys",
    id_token_validation = TRUE,
    use_pkce = TRUE
  )
  local_mocked_bindings(
    oauth_provider_oidc_discover = function(url, ...) {
      issuer <<- url
      provider
    },
    .package = "shinyOAuth"
  )
  client <- oauth_db_salesforce_client(
    "app",
    "http://localhost:8100",
    "secret",
    data_cloud = TRUE
  )
  expect_identical(issuer, "https://login.salesforce.com")
  expect_identical(client@provider, provider)
  expect_setequal(
    client@scopes,
    c("openid", "profile", "api", "refresh_token", "cdp_query_api")
  )
  expect_true(client@provider@use_pkce)
  custom <- oauth_db_salesforce_client(
    "app",
    "http://localhost:8100",
    "secret",
    provider = provider,
    login_url = stop("replaced"),
    data_cloud = stop("replaced"),
    scopes = "api"
  )
  expect_identical(custom@scopes, "api")
  expect_error(
    oauth_db_salesforce_client("app", "http://localhost:8100", data_cloud = NA),
    "TRUE or FALSE"
  )
})

test_that("CRM queries fetch all pages with fresh visitor tokens and retain nested values", {
  requests <- list()
  auth <- NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 1L) {
      auth$token(auth$make_token("renewed"))
      salesforce_response(list(
        totalSize = 2L,
        done = FALSE,
        records = list(list(
          attributes = list(type = "Account"),
          Id = "A",
          Name = "Alice",
          Parent = list(Name = "North")
        )),
        nextRecordsUrl = "/services/data/v64.0/query/locator-1"
      ))
    } else {
      salesforce_response(list(
        totalSize = 2L,
        done = TRUE,
        records = list(list(Id = "B", Name = "Bob", Parent = NULL))
      ))
    }
  })
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(session, scopes = "api")
    api <- oauth_db_salesforce_api(auth$connection, "https://org.example/")
    expect_identical(length(requests), 0L)
    rows <- api$query("SELECT Id, Name, Parent.Name FROM Account")
    expect_identical(rows$Id, c("A", "B"))
    expect_identical(rows$Name, c("Alice", "Bob"))
    expect_identical(rows$Parent, list(list(Name = "North"), NULL))
    expect_false("attributes" %in% names(rows))
    expect_match(requests[[1L]]$url, "/query?q=", fixed = TRUE)
    expect_identical(
      requests[[2L]]$url,
      "https://org.example/services/data/v64.0/query/locator-1"
    )
    expect_identical(
      httr2::req_get_headers(requests[[1L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A"
    )
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer renewed"
    )
    expect_false(requests[[1L]]$options$followlocation)
    expect_output(print(api), "<OAuthSalesforceAPI>")
  })
})

test_that("CRM discovery, deleted records and count-only queries use native responses", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (grepl("queryAll", req$url, fixed = TRUE)) {
      salesforce_response(list(totalSize = 12L, done = TRUE, records = list()))
    } else {
      salesforce_response(list(name = "Account", queryable = TRUE))
    }
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_api(
      odb_test_authorization(session, scopes = "api")$connection,
      "https://org.example"
    )
    expect_identical(api$objects()$name, "Account")
    expect_identical(api$describe("Account")$queryable, TRUE)
    result <- api$query(
      "SELECT COUNT() FROM Account",
      include_deleted = TRUE,
      raw = TRUE
    )
    expect_identical(result$totalSize, 12L)
    expect_identical(result$records, list())
    expect_match(requests[[2L]]$url, "/sobjects/Account/describe", fixed = TRUE)
    expect_match(requests[[3L]]$url, "/queryAll?q=", fixed = TRUE)
    expect_error(api$describe("Account/../../userinfo"), "API name")
  })
})

test_that("CRM locators cannot redirect credentials or cause pagination cycles", {
  for (locator in c(
    "https://other.example/steal",
    "//other.example/steal",
    "/services/data/v65.0/query/id",
    "/services/data/v64.0/query/../id",
    "/services/data/v64.0/query/%2e%2e",
    "/services/data/v64.0/query/id?token=bad"
  )) {
    local({
      calls <- 0L
      httr2::local_mocked_responses(function(req) {
        calls <<- calls + 1L
        salesforce_response(list(
          totalSize = 2L,
          done = FALSE,
          records = list(list(Id = "A")),
          nextRecordsUrl = locator
        ))
      })
      odb_test_domain(function(session) {
        api <- oauth_db_salesforce_api(
          odb_test_authorization(session, scopes = "api")$connection,
          "https://org.example"
        )
        expect_error(
          api$query("SELECT Id FROM Account"),
          class = "shinyOAuthDB_invalid_response"
        )
        expect_identical(calls, 1L)
      })
    })
  }
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    salesforce_response(list(
      totalSize = 3L,
      done = FALSE,
      records = list(list(Id = "A")),
      nextRecordsUrl = "/services/data/v64.0/query/repeated"
    ))
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_api(
      odb_test_authorization(session, scopes = "api")$connection,
      "https://org.example"
    )
    expect_error(
      api$query("SELECT Id FROM Account"),
      class = "shinyOAuthDB_invalid_response"
    )
    expect_identical(calls, 2L)
  })
})

test_that("Data Cloud submits bound SQL, polls and fetches pages without double-encoding query IDs", {
  requests <- list()
  auth <- NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 1L) {
      expect_identical(httr2::req_get_method(req), "POST")
      auth$token(auth$make_token("rotated"))
      salesforce_response(salesforce_fixture(
        list(list("Alice")),
        finished = FALSE,
        count = 3L
      ))
    } else if (length(requests) == 2L) {
      salesforce_response(salesforce_fixture(count = 3L)$status)
    } else {
      salesforce_response(list(
        returnedRows = 2L,
        data = list(list("Bob"), list("Cara"))
      ))
    }
  })
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(session, scopes = c("api", "cdp_query_api"))
    api <- oauth_db_salesforce_data_cloud_api(
      auth$connection,
      "https://org.example",
      dataspace = "reporting",
      page_size = 2L
    )
    parameters <- list(list(
      name = "since",
      type = "date",
      value = "2026-01-01"
    ))
    rows <- api$query(
      "SELECT name FROM people WHERE created >= :since",
      parameters
    )
    expect_identical(rows$name, c("Alice", "Bob", "Cara"))
    body <- requests[[1L]]$body$data
    expect_identical(body$sqlParameters, parameters)
    expect_identical(body$rowLimit, 2L)
    expect_true(requests[[1L]]$options$fresh_connect)
    expect_true(requests[[1L]]$options$forbid_reuse)
    expect_match(requests[[2L]]$url, "/query%2Fone?", fixed = TRUE)
    expect_false(grepl("%252F", requests[[2L]]$url, fixed = TRUE))
    expect_match(requests[[3L]]$url, "offset=1", fixed = TRUE)
    expect_match(requests[[3L]]$url, "dataspace=reporting", fixed = TRUE)
    expect_identical(
      httr2::req_get_headers(requests[[3L]], redacted = "reveal")$Authorization,
      "Bearer rotated"
    )
    expect_output(print(api), "<OAuthSalesforceDataCloudAPI>")
  })
})

test_that("Data Cloud preserves exact numbers, typed empty results and native nested values", {
  body <- '{"returnedRows":1,"status":{"queryId":"id","completionStatus":"Finished","rowCount":1},"metadata":[{"name":"id","type":"bigint"},{"name":"amount","type":"numeric"},{"name":"n","type":"integer"},{"name":"ok","type":"bool"},{"name":"date","type":"date"},{"name":"nested","type":"array"}],"data":[[9223372036854775807,1.234567890123456789,2,true,"2026-11-08",[9007199254740993]]]}'
  httr2::local_mocked_responses(function(req) odb_http_response(body))
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_data_cloud_api(
      odb_test_authorization(
        session,
        scopes = c("api", "cdp_query_api")
      )$connection,
      "https://org.example"
    )
    rows <- api$query("SELECT values")
    expect_identical(rows$id, "9223372036854775807")
    expect_identical(rows$amount, "1.234567890123456789")
    expect_identical(rows$n, 2)
    expect_identical(rows$ok, TRUE)
    expect_identical(rows$date, "2026-11-08")
    expect_identical(rows$nested, list(list("9007199254740993")))
    expect_identical(
      api$query("SELECT values", raw = TRUE)$data[[1L]][[2L]],
      "1.234567890123456789"
    )
    body <<- '{"returnedRows":0,"status":{"queryId":"id","completionStatus":"Finished","rowCount":0},"metadata":[{"name":"n","type":"integer"},{"name":"ok","type":"bool"},{"name":"text","type":"varchar"}],"data":[]}'
    empty <- api$query("SELECT values WHERE false")
    expect_identical(empty$n, numeric())
    expect_identical(empty$ok, logical())
    expect_identical(empty$text, character())
    expect_identical(
      api$query("SELECT values WHERE false", raw = TRUE)$data,
      list()
    )
  })
})

test_that("Salesforce read retries renew once while SQL submissions never replay", {
  for (cloud in c(FALSE, TRUE)) {
    local({
      requests <- 0L
      httr2::local_mocked_responses(function(req) {
        requests <<- requests + 1L
        if (requests == 1L) {
          return(odb_http_response("PRIVATE_ERROR_BODY", 401L))
        }
        salesforce_response(list(
          totalSize = 1L,
          done = TRUE,
          records = list(list(Id = "A"))
        ))
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(
          session,
          scopes = c("api", "cdp_query_api"),
          refresh_token = "fixture-refresh"
        )
        if (cloud) {
          api <- oauth_db_salesforce_data_cloud_api(
            auth$connection,
            "https://org.example"
          )
          error <- expect_error(
            api$query("SELECT value"),
            class = "shinyOAuthDB_request_failed"
          )
          expect_false(grepl(
            "PRIVATE_ERROR_BODY",
            conditionMessage(error),
            fixed = TRUE
          ))
          expect_identical(requests, 1L)
          expect_identical(auth$calls$acquire, 0L)
        } else {
          api <- oauth_db_salesforce_api(auth$connection, "https://org.example")
          expect_identical(api$query("SELECT Id FROM Account")$Id, "A")
          expect_identical(requests, 2L)
          expect_identical(auth$calls$acquire, 1L)
        }
      })
    })
  }
})

test_that("Salesforce discards responses when authorization changes during a request", {
  for (cloud in c(FALSE, TRUE)) {
    local({
      requests <- 0L
      selected <- NULL
      replacement <- NULL
      httr2::local_mocked_responses(function(req) {
        requests <<- requests + 1L
        selected(replacement$connection)
        if (cloud) {
          salesforce_response(salesforce_fixture())
        } else {
          salesforce_response(list(
            totalSize = 1L,
            done = TRUE,
            records = list(list(Id = "A"))
          ))
        }
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(
          session,
          scopes = c("api", "cdp_query_api")
        )
        replacement <<- odb_test_authorization(
          session,
          id = "B",
          scopes = auth$scopes
        )
        selected <<- shiny::reactiveVal(NULL)
        make <- if (cloud) {
          oauth_db_salesforce_data_cloud_api
        } else {
          oauth_db_salesforce_api
        }
        api <- make(selected, "https://org.example")
        expect_error(
          api$query("SELECT something"),
          class = "shiny.silent.error"
        )
        selected(auth$connection)
        expect_error(
          api$query("SELECT something"),
          class = "shinyOAuthDB_authorization_unavailable"
        )
        expect_identical(requests, 1L)
        selected(NULL)
        expect_error(
          api$query("SELECT something"),
          class = "shiny.silent.error"
        )
      })
    })
  }
})

test_that("Salesforce validates configuration and parameters before token or network access", {
  for (make in list(
    oauth_db_salesforce_api,
    oauth_db_salesforce_data_cloud_api
  )) {
    for (url in c(
      "http://org.example",
      "https://user:secret@org.example",
      "https://org.example/path",
      "https://org.example?token=secret"
    )) {
      expect_error(
        make(stop("unused authorization"), url),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(
      make(NULL, "https://org.example", api_version = "64.0/../../"),
      "api_version"
    )
    expect_error(make(NULL, "https://org.example", timeout = 0), "positive")
  }
  expect_error(
    oauth_db_salesforce_data_cloud_api(
      NULL,
      "https://org.example",
      api_version = "63.0"
    ),
    "64.0"
  )
  expect_error(
    oauth_db_salesforce_data_cloud_api(
      NULL,
      "https://org.example",
      page_size = Inf
    ),
    "positive integer"
  )
  for (parameters in list(
    list(x = 1),
    list(list(name = "n", type = "integer", value = 1)),
    list(
      list(name = "n", type = "integer", value = "1"),
      list(name = "n", type = "integer", value = "2")
    )
  )) {
    expect_error(
      .odb_salesforce_parameters(parameters),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
})

test_that("Data Cloud rejects incomplete pages, changed jobs and malformed cells even in raw mode", {
  for (scenario in c(
    "empty_page",
    "changed_job",
    "bad_count",
    "bad_cell",
    "bad_metadata",
    "bad_json",
    "failed"
  )) {
    local({
      calls <- 0L
      httr2::local_mocked_responses(function(req) {
        calls <<- calls + 1L
        if (scenario == "bad_json") {
          return(odb_http_response("{bad"))
        }
        result <- salesforce_fixture(
          count = 2L,
          finished = scenario != "changed_job"
        )
        if (scenario == "bad_count") {
          result$returnedRows <- 2L
        }
        if (scenario == "bad_cell") {
          result$data <- list(list(list(secret = "PRIVATE")))
        }
        if (scenario == "bad_metadata") {
          result$metadata <- list(list(name = "x"))
        }
        if (scenario == "failed") {
          result$status$completionStatus <- "Failed"
        }
        if (scenario == "changed_job" && calls == 2L) {
          return(salesforce_response(salesforce_fixture(id = "another")$status))
        }
        if (calls > 1L) {
          return(salesforce_response(list(returnedRows = 0L, data = list())))
        }
        salesforce_response(result)
      })
      odb_test_domain(function(session) {
        api <- oauth_db_salesforce_data_cloud_api(
          odb_test_authorization(
            session,
            scopes = c("api", "cdp_query_api")
          )$connection,
          "https://org.example"
        )
        expect_error(
          api$query("SELECT something", raw = TRUE),
          class = if (scenario == "failed") {
            "shinyOAuthDB_query_failed"
          } else {
            "shinyOAuthDB_invalid_response"
          }
        )
        expect_lte(calls, 2L)
      })
    })
  }
})

test_that("Salesforce applies one deadline to submission, polling and pagination", {
  for (cloud in c(FALSE, TRUE)) {
    local({
      now <- 0
      calls <- 0L
      local_mocked_bindings(.odb_http_time = function() now)
      httr2::local_mocked_responses(function(req) {
        calls <<- calls + 1L
        now <<- now + 6
        if (cloud) {
          salesforce_response(salesforce_fixture(finished = FALSE, count = 2L))
        } else {
          salesforce_response(list(
            totalSize = 2L,
            done = FALSE,
            records = list(list(Id = "A")),
            nextRecordsUrl = "/services/data/v64.0/query/next"
          ))
        }
      })
      odb_test_domain(function(session) {
        make <- if (cloud) {
          oauth_db_salesforce_data_cloud_api
        } else {
          oauth_db_salesforce_api
        }
        api <- make(
          odb_test_authorization(
            session,
            scopes = c("api", "cdp_query_api")
          )$connection,
          "https://org.example",
          timeout = 10
        )
        expect_error(
          api$query("SELECT something"),
          class = "shinyOAuthDB_timeout"
        )
        expect_identical(calls, 2L)
      })
    })
  }
})

test_that("Salesforce credential renewal consumes the operation deadline", {
  operations <- list(
    query = function(api) api$query("SELECT Id FROM Account"),
    query_all = function(api) {
      api$query("SELECT Id FROM Account", include_deleted = TRUE)
    },
    objects = function(api) api$objects(),
    describe = function(api) api$describe("Account"),
    cloud = function(api) api$query("SELECT name FROM people")
  )
  for (name in names(operations)) {
    for (delay in c(0.25, 1, 20)) {
      local({
        now <- 0
        requests <- list()
        local_mocked_bindings(.odb_http_time = function() now)
        httr2::local_mocked_responses(function(req) {
          requests[[length(requests) + 1L]] <<- req
          if (name == "cloud") {
            salesforce_response(salesforce_fixture())
          } else if (name %in% c("query", "query_all")) {
            salesforce_response(list(
              totalSize = 1L,
              done = TRUE,
              records = list(list(Id = "A"))
            ))
          } else {
            salesforce_response(list(name = "Account"))
          }
        })
        odb_test_domain(function(session) {
          auth <- odb_test_authorization(
            session,
            scopes = c("api", "cdp_query_api"),
            refresh_token = "fixture-refresh",
            acquire = function(...) {
              now <<- now + delay
              auth$token(auth$make_token("renewed"))
              TRUE
            }
          )
          make <- if (name == "cloud") {
            oauth_db_salesforce_data_cloud_api
          } else {
            oauth_db_salesforce_api
          }
          api <- make(auth$connection, "https://org.example", timeout = 1)
          auth$token(auth$make_token("short-lived", lifetime = 30))
          operation <- operations[[name]]
          if (delay >= 1) {
            expect_error(operation(api), class = "shinyOAuthDB_timeout")
            expect_length(requests, 0L)
          } else {
            expect_no_error(operation(api))
            expect_length(requests, 1L)
            expect_equal(requests[[1L]]$options$timeout_ms, 750)
          }
          expect_identical(auth$calls$acquire, 1L)
        })
      })
    }
  }
})

test_that("Salesforce forwards JWT access tokens and hides no legacy-token workaround", {
  # Synthetic JWT-shaped credential, not an ID token or a signed live token.
  credential <- "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJmaXh0dXJlIn0.c2lnbmF0dXJl"
  headers <- character()
  httr2::local_mocked_responses(function(req) {
    headers <<- c(
      headers,
      httr2::req_get_headers(req, redacted = "reveal")$Authorization
    )
    if (grepl("ssot/query-sql", req$url, fixed = TRUE)) {
      salesforce_response(salesforce_fixture())
    } else {
      salesforce_response(list(
        totalSize = 1L,
        done = TRUE,
        records = list(list(Id = "A"))
      ))
    }
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = c("api", "cdp_query_api"))
    auth$token(auth$make_token(credential))
    oauth_db_salesforce_api(auth$connection, "https://org.example")$query(
      "SELECT Id FROM Account"
    )
    oauth_db_salesforce_data_cloud_api(
      auth$connection,
      "https://org.example"
    )$query("SELECT name")
    expect_identical(headers, rep(paste("Bearer", credential), 2L))
    expect_error(auth$make_token("00Dfixture!legacy"), class = "error")
  })
})

test_that("Salesforce stops on scope loss or session end during page retrieval", {
  for (cloud in c(FALSE, TRUE)) {
    for (end_session in c(FALSE, TRUE)) {
      local({
        requests <- 0L
        auth <- owner <- NULL
        httr2::local_mocked_responses(function(req) {
          requests <<- requests + 1L
          if (requests == 2L) {
            if (end_session) {
              owner$close()
            } else {
              auth$token(auth$make_token("denied", character()))
            }
          }
          if (cloud) {
            if (requests == 1L) {
              salesforce_response(salesforce_fixture(
                finished = FALSE,
                count = 2L
              ))
            } else {
              salesforce_response(salesforce_fixture(count = 2L)$status)
            }
          } else {
            salesforce_response(list(
              totalSize = 2L,
              done = FALSE,
              records = list(list(Id = "A")),
              nextRecordsUrl = "/services/data/v64.0/query/next"
            ))
          }
        })
        odb_test_domain(function(session) {
          owner <<- session
          auth <<- odb_test_authorization(
            session,
            scopes = c("api", "cdp_query_api")
          )
          make <- if (cloud) {
            oauth_db_salesforce_data_cloud_api
          } else {
            oauth_db_salesforce_api
          }
          api <- make(auth$connection, "https://org.example")
          expect_error(
            api$query("SELECT something"),
            class = "shinyOAuthDB_authorization_unavailable"
          )
          expect_identical(requests, 2L)
        })
      })
    }
  }
})

test_that("Data Cloud polling and result reads can renew tokens without replaying SQL", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    switch(
      as.character(length(requests)),
      `1` = salesforce_response(salesforce_fixture(
        finished = FALSE,
        count = 2L
      )),
      `2` = odb_http_response("private", 401L),
      `3` = salesforce_response(salesforce_fixture(count = 2L)$status),
      `4` = salesforce_response(list(
        returnedRows = 1L,
        data = list(list("Bob"))
      ))
    )
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      scopes = c("api", "cdp_query_api"),
      refresh_token = "fixture-refresh"
    )
    api <- oauth_db_salesforce_data_cloud_api(
      auth$connection,
      "https://org.example"
    )
    expect_identical(api$query("SELECT name")$name, c("visible", "Bob"))
    expect_identical(auth$calls$acquire, 1L)
    expect_identical(
      sum(vapply(requests, httr2::req_get_method, "") == "POST"),
      1L
    )
    expect_identical(
      httr2::req_get_headers(requests[[4L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A-acquired"
    )
  })
})
