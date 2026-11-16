crm_page <- function(records, total = length(records), next_url = NULL) {
  list(
    totalSize = total,
    done = is.null(next_url),
    records = records,
    nextRecordsUrl = next_url
  )
}

crm_response <- function(page) {
  odb_http_response(jsonlite::toJSON(page, auto_unbox = TRUE, null = "null"))
}

test_that("CRM completes outer and nested query pages with current visitor tokens", {
  for (raw in c(FALSE, TRUE)) {
    local({
      requests <- list()
      auth <- NULL
      prefix <- "/services/data/v64.0/query"
      httr2::local_mocked_responses(function(req) {
        requests[[length(requests) + 1L]] <<- req
        page <- switch(
          httr2::url_parse(req$url)$path,
          "/services/data/v64.0/query" = crm_page(
            list(list(
              Id = "A",
              Parent = list(Name = "North"),
              Contacts = crm_page(
                list(list(Id = "C1")),
                2L,
                paste0(prefix, "/contacts")
              )
            )),
            2L,
            paste0(prefix, "/accounts")
          ),
          "/services/data/v64.0/query/accounts" = crm_page(
            list(list(Id = "B", Contacts = crm_page(list()), Parent = NULL)),
            2L
          ),
          "/services/data/v64.0/query/contacts" = {
            auth$token(auth$make_token("renewed"))
            crm_page(
              list(list(
                Id = "C2",
                Cases = crm_page(
                  list(list(Id = "Q1")),
                  2L,
                  paste0(prefix, "/cases")
                )
              )),
              2L
            )
          },
          "/services/data/v64.0/query/cases" = crm_page(
            list(list(Id = "Q2")),
            2L
          ),
          stop("Unexpected query locator")
        )
        crm_response(page)
      })
      odb_test_domain(function(session) {
        auth <<- odb_test_authorization(session, scopes = "api")
        api <- oauth_db_salesforce_api(auth$connection, "https://org.example")
        result <- api$query(
          "SELECT Id, (SELECT Id, (SELECT Id FROM Cases) FROM Contacts) FROM Account",
          raw = raw
        )
        contacts <- if (raw) {
          result$records[[1L]]$Contacts
        } else {
          result$Contacts[[1L]]
        }
        expect_true(contacts$done)
        expect_null(contacts$nextRecordsUrl)
        expect_identical(
          vapply(contacts$records, `[[`, "", "Id"),
          c("C1", "C2")
        )
        cases <- contacts$records[[2L]]$Cases
        expect_true(cases$done)
        expect_null(cases$nextRecordsUrl)
        expect_identical(vapply(cases$records, `[[`, "", "Id"), c("Q1", "Q2"))
        empty <- if (raw) {
          result$records[[2L]]$Contacts
        } else {
          result$Contacts[[2L]]
        }
        expect_identical(empty$records, list())
        if (raw) {
          expect_true(result$done)
          expect_null(result$nextRecordsUrl)
        } else {
          expect_identical(result$Id, c("A", "B"))
          expect_null(result$Parent[[2L]])
        }
      })
      expect_length(requests, 4L)
      expect_identical(
        vapply(
          requests,
          function(req) {
            httr2::req_get_headers(req, redacted = "reveal")$Authorization
          },
          ""
        ),
        c(
          "Bearer fixture-A",
          "Bearer fixture-A",
          "Bearer fixture-A",
          "Bearer renewed"
        )
      )
    })
  }
})

test_that("CRM aggregate aliases are not interpreted as query envelopes", {
  httr2::local_mocked_responses(function(req) {
    crm_response(crm_page(list(list(
      attributes = list(type = "AggregateResult"),
      totalSize = 2L,
      done = 3L,
      records = 4L
    ))))
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_api(
      odb_test_authorization(session, scopes = "api")$connection,
      "https://org.example"
    )
    expect_identical(
      api$query(
        "SELECT COUNT(Id) totalSize, MIN(Amount) done, MAX(Amount) records FROM Opportunity"
      ),
      data.frame(totalSize = 2, done = 3, records = 4)
    )
  })
})

test_that("CRM rejects unsafe nested locators, cycles and inconsistent child counts", {
  for (locator in c(
    "https://other.example/steal",
    "//other.example/steal",
    "/services/data/v65.0/query/id",
    "/services/data/v64.0/query/../id",
    "/services/data/v64.0/query/%2e%2e",
    "/services/data/v64.0/query/id?token=bad",
    "/services/data/v64.0/query/repeated"
  )) {
    local({
      calls <- 0L
      child <- crm_page(list(list(Id = "C1")), 3L, locator)
      httr2::local_mocked_responses(function(req) {
        calls <<- calls + 1L
        crm_response(
          if (calls == 1L) {
            crm_page(list(list(Id = "A", Contacts = child)))
          } else {
            child
          }
        )
      })
      odb_test_domain(function(session) {
        api <- oauth_db_salesforce_api(
          odb_test_authorization(session, scopes = "api")$connection,
          "https://org.example"
        )
        expect_error(
          api$query("SELECT Id, (SELECT Id FROM Contacts) FROM Account"),
          class = "shinyOAuthDB_invalid_response"
        )
        expect_identical(calls, if (endsWith(locator, "/repeated")) 2L else 1L)
      })
    })
  }
  local({
    child <- crm_page(list(list(Id = "C1")), 2L)
    httr2::local_mocked_responses(function(req) {
      crm_response(crm_page(list(list(Id = "A", Contacts = child))))
    })
    odb_test_domain(function(session) {
      api <- oauth_db_salesforce_api(
        odb_test_authorization(session, scopes = "api")$connection,
        "https://org.example"
      )
      for (value in list(
        crm_page(list(), 2L),
        crm_page(list(), 2L, "/services/data/v64.0/query/empty"),
        list(totalSize = 1L, done = TRUE),
        crm_page(list(list(Id = "C1")), 2L)
      )) {
        child <<- value
        expect_error(
          api$query("SELECT Id, (SELECT Id FROM Contacts) FROM Account"),
          class = "shinyOAuthDB_invalid_response"
        )
      }
    })
  })
})

test_that("nested CRM requests retain the original authorization and operation deadline", {
  for (transition in c(
    "replace",
    "logout",
    "permissions",
    "session_end",
    "timeout"
  )) {
    local({
      now <- 0
      calls <- 0L
      auth <- selected <- session_owner <- replacement <- NULL
      local_mocked_bindings(.odb_http_time = function() now)
      httr2::local_mocked_responses(function(req) {
        calls <<- calls + 1L
        if (calls == 1L) {
          now <<- 4
          return(crm_response(crm_page(list(list(
            Id = "A",
            Contacts = crm_page(
              list(list(Id = "C1")),
              2L,
              "/services/data/v64.0/query/contacts"
            )
          )))))
        }
        expect_equal(req$options$timeout_ms, 6000)
        switch(
          transition,
          replace = selected(replacement$connection),
          logout = selected(NULL),
          permissions = auth$token(auth$make_token("denied", character())),
          session_end = session_owner$close(),
          timeout = {
            now <<- 10
          }
        )
        crm_response(crm_page(list(list(Id = "C2")), 2L))
      })
      odb_test_domain(function(session) {
        session_owner <<- session
        auth <<- odb_test_authorization(session, scopes = "api")
        replacement <<- odb_test_authorization(
          session,
          id = "B",
          scopes = "api"
        )
        selected <<- shiny::reactiveVal(auth$connection)
        api <- oauth_db_salesforce_api(
          selected,
          "https://org.example",
          timeout = 10
        )
        expect_error(
          api$query("SELECT Id, (SELECT Id FROM Contacts) FROM Account"),
          class = if (transition == "timeout") {
            "shinyOAuthDB_timeout"
          } else {
            "shinyOAuthDB_authorization_unavailable"
          }
        )
        expect_identical(calls, 2L)
      })
    })
  }
})
