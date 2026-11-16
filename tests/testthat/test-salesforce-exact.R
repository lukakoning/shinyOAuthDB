test_that("CRM exact mode preserves decimal lexemes in outer and nested query pages", {
  for (raw in c(FALSE, TRUE)) {
    local({
      requests <- list()
      pages <- c(
        paste0(
          '{"totalSize":2,"done":false,"records":[{"Id":"A",',
          '"Amount":1234567890123456.78,"Ratio":1.234567890123456789e-10,',
          '"Count":9007199254740993,"Enabled":true,"Missing":null,',
          '"Note":"price 12.34 and \\"123\\"",',
          '"Contacts":{"totalSize":2,"done":false,',
          '"records":[{"Id":"C1","Amount":-0.000000000000000001}],',
          '"nextRecordsUrl":"/services/data/v64.0/query/contacts"}}],',
          '"nextRecordsUrl":"/services/data/v64.0/query/accounts"}'
        ),
        paste0(
          '{"totalSize":2,"done":true,"records":[{"Id":"B","Amount":null,',
          '"Ratio":2e+3,"Count":2,"Enabled":false,"Missing":null,',
          '"Note":"12.34","Contacts":null}]}'
        ),
        '{"totalSize":2,"done":true,"records":[{"Id":"C2","Amount":-0.0}]}'
      )
      httr2::local_mocked_responses(function(req) {
        requests[[length(requests) + 1L]] <<- req
        odb_http_response(pages[[length(requests)]])
      })
      odb_test_domain(function(session) {
        api <- oauth_db_salesforce_api(
          odb_test_authorization(session, scopes = "api")$connection,
          "https://org.example"
        )
        result <- api$query(
          "SELECT Id, Amount, (SELECT Id, Amount FROM Contacts) FROM Account",
          include_deleted = raw,
          raw = raw,
          exact = TRUE
        )
        record <- if (raw) result$records[[1L]] else lapply(result, `[[`, 1L)
        expect_identical(record$Amount, "1234567890123456.78")
        expect_identical(record$Ratio, "1.234567890123456789e-10")
        expect_identical(record$Count, "9007199254740993")
        expect_true(record$Enabled)
        expect_identical(record$Note, 'price 12.34 and "123"')
        contacts <- record$Contacts
        expect_true(contacts$done)
        expect_identical(
          vapply(contacts$records, `[[`, "", "Amount"),
          c("-0.000000000000000001", "-0.0")
        )
        if (raw) {
          expect_identical(result$totalSize, "2")
          expect_null(result$records[[2L]]$Amount)
          expect_null(record$Missing)
        } else {
          expect_identical(
            result$Amount,
            c("1234567890123456.78", NA_character_)
          )
          expect_identical(result$Ratio, c("1.234567890123456789e-10", "2e+3"))
          expect_identical(result$Count, c("9007199254740993", "2"))
          expect_identical(result$Enabled, c(TRUE, FALSE))
          expect_identical(result$Missing, c(NA, NA))
        }
      })
      expect_length(requests, 3L)
      expect_match(
        requests[[1L]]$url,
        if (raw) "/queryAll?q=" else "/query?q=",
        fixed = TRUE
      )
      expect_identical(
        httr2::url_parse(requests[[2L]]$url)$path,
        "/services/data/v64.0/query/accounts"
      )
      expect_identical(
        httr2::url_parse(requests[[3L]]$url)$path,
        "/services/data/v64.0/query/contacts"
      )
    })
  }
})

test_that("CRM keeps numeric defaults and validates exact mode before making requests", {
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    odb_http_response('{"totalSize":1,"done":true,"records":[{"Amount":12.5}]}')
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_api(
      odb_test_authorization(session, scopes = "api")$connection,
      "https://org.example"
    )
    for (value in list(NA, 1, character(), "true")) {
      expect_error(
        api$query("SELECT Amount FROM Opportunity", exact = value),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_identical(requests, 0L)
    expect_identical(api$query("SELECT Amount FROM Opportunity")$Amount, 12.5)
    expect_identical(
      api$query("SELECT Amount FROM Opportunity", raw = TRUE)$records[[
        1L
      ]]$Amount,
      12.5
    )
    expect_identical(
      api$query("SELECT Amount FROM Opportunity", exact = TRUE)$Amount,
      "12.5"
    )
  })
})

test_that("CRM exact results are available through background tasks", {
  task_app_workers()
  httr2::local_mocked_responses(function(req) {
    odb_http_response(
      '{"totalSize":1,"done":true,"records":[{"Amount":1234567890123456.78}]}'
    )
  })
  odb_test_domain(function(session) {
    api <- oauth_db_salesforce_api(
      odb_test_authorization(session, scopes = "api")$connection,
      "https://org.example"
    )
    task <- oauth_db_task(api)
    expect_true(task$invoke("SELECT Amount FROM Opportunity", exact = TRUE))
    task_app_flush(session)
    expect_identical(task$status(), "success")
    expect_identical(task$result()$Amount, "1234567890123456.78")
  })
})
