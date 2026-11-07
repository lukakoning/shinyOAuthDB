libsql_test_result <- function(
  cols = list(list(name = "id", decltype = "INTEGER")),
  rows = list(list(list(type = "integer", value = "42")))
) {
  list(
    cols = cols,
    rows = rows,
    affected_row_count = 0L,
    last_insert_rowid = NULL
  )
}

libsql_test_response <- function(
  result = libsql_test_result(),
  modify = identity
) {
  body <- list(
    baton = NULL,
    base_url = "https://untrusted.example/",
    results = list(
      list(type = "ok", response = list(type = "execute", result = result)),
      list(type = "ok", response = list(type = "close"))
    )
  )
  odb_http_response(as.character(jsonlite::toJSON(
    modify(body),
    auto_unbox = TRUE,
    null = "null"
  )))
}

test_that("libSQL binds native values separately and closes each HTTP stream", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    libsql_test_response()
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_libsql_api(
      auth$connection,
      "libsql://db.example/proxy/",
      ca_bundle = "ca.pem",
      timeout = 10
    )
    expect_s3_class(api, "OAuthLibSQLAPI")
    result <- api$query(
      "SELECT :country, :id",
      parameters = list(
        country = "NL'; DROP TABLE orders; --",
        id = I("9223372036854775807")
      )
    )
    expect_identical(result$id, "42")
    raw <- api$query("SELECT ?", list(1L), raw = TRUE)
    expect_identical(raw$cols[[1L]]$decltype, "INTEGER")
    api$execute(
      "INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?, ?)",
      list(1L, TRUE, 1.25, "text", as.raw(c(0, 255)), NULL, NA)
    )
    expect_output(print(api), "<OAuthLibSQLAPI>")
  })
  req <- requests[[1L]]
  expect_identical(req$url, "https://db.example/proxy/v2/pipeline")
  expect_identical(
    httr2::req_get_headers(req, redacted = "reveal")$Authorization,
    "Bearer fixture-A"
  )
  expect_false(req$options$followlocation)
  expect_true(req$options$fresh_connect)
  expect_true(req$options$forbid_reuse)
  expect_identical(req$options$cainfo, "ca.pem")
  body <- req$body$data
  expect_null(body$baton)
  expect_identical(body$requests[[2L]], list(type = "close"))
  expect_identical(
    body$requests[[1L]]$stmt$named_args[[1L]],
    list(
      name = "country",
      value = list(type = "text", value = "NL'; DROP TABLE orders; --")
    )
  )
  expect_identical(
    body$requests[[1L]]$stmt$named_args[[2L]]$value,
    list(type = "integer", value = "9223372036854775807")
  )
  stmt <- requests[[3L]]$body$data$requests[[1L]]$stmt
  expect_false(stmt$want_rows)
  expect_identical(
    stmt$args,
    list(
      list(type = "integer", value = "1"),
      list(type = "integer", value = "1"),
      list(type = "float", value = 1.25),
      list(type = "text", value = "text"),
      list(type = "blob", base64 = "AP8"),
      list(type = "null"),
      list(type = "null")
    )
  )
  expect_true(all(vapply(
    requests,
    function(req) identical(req$url, requests[[1L]]$url),
    logical(1)
  )))
  expect_true(all(vapply(
    requests,
    function(req) is.null(req$body$data$baton),
    logical(1)
  )))
})

test_that("libSQL preserves exact integers, binary data, mixed types and empty metadata", {
  kinds <- c("integer", "float", "text", "blob", "null", "integer")
  values <- list(
    list(type = "integer", value = "-9223372036854775808"),
    list(type = "float", value = 1.25),
    list(type = "text", value = "hello"),
    list(type = "blob", base64 = "AP8"),
    list(type = "null"),
    list(type = "integer", value = "1")
  )
  result <- libsql_test_result(
    lapply(seq_along(kinds), function(i) list(name = paste0("c", i))),
    list(
      values,
      c(
        rep(list(list(type = "null")), 5L),
        list(list(type = "text", value = "text"))
      )
    )
  )
  httr2::local_mocked_responses(function(req) libsql_test_response(result))
  odb_test_domain(function(session) {
    api <- oauth_db_libsql_api(
      odb_test_authorization(session)$connection,
      "https://db.example"
    )
    rows <- api$query("SELECT values")
    expect_identical(rows$c1, c("-9223372036854775808", NA_character_))
    expect_identical(rows$c2, c(1.25, NA_real_))
    expect_identical(rows$c3, c("hello", NA_character_))
    expect_identical(rows$c4, list(as.raw(c(0, 255)), NULL))
    expect_identical(rows$c5, c(NA, NA))
    expect_identical(rows$c6, list("1", "text"))
    result$rows <<- list()
    empty <- api$query("SELECT values WHERE 0")
    expect_identical(dim(empty), c(0L, 6L))
    expect_named(empty, paste0("c", 1:6))
    result$cols <<- list()
    expect_identical(api$execute("CREATE TABLE t(x)")$affected_row_count, 0L)
  })
})

test_that("libSQL renews tokens before submission and never retries SQL failures", {
  requests <- list()
  status <- 200L
  fail_sql <- FALSE
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (status != 200L) {
      return(odb_http_response("response-secret", status))
    }
    libsql_test_response(modify = function(body) {
      if (fail_sql) {
        body$results[[1L]] <- list(
          type = "error",
          error = list(message = "response-secret")
        )
      }
      body
    })
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      target = "sqlite",
      refresh_token = "fixture-refresh"
    )
    api <- oauth_db_libsql_api(
      auth$connection,
      "https://db.example",
      target = "sqlite",
      required_scopes = auth$scopes
    )
    auth$token(auth$make_token("expired", lifetime = 0))
    expect_identical(api$query("SELECT 42")$id, "42")
    expect_identical(auth$calls$acquire, 1L)
    auth$token(auth$make_token("rotated"))
    api$query("SELECT 42")
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer rotated"
    )
    for (value in c(401L, 403L, 302L, 503L)) {
      status <<- value
      error <- expect_error(
        api$execute("INSERT INTO orders VALUES (1)"),
        class = "shinyOAuthDB_request_failed"
      )
      expect_false(grepl(
        "response-secret|fixture|rotated",
        conditionMessage(error)
      ))
      expect_null(error$parent)
    }
    expect_identical(auth$calls$acquire, 1L)
    status <<- 200L
    fail_sql <<- TRUE
    error <- expect_error(
      api$query("SELECT 42", raw = TRUE),
      class = "shinyOAuthDB_query_failed"
    )
    expect_false(grepl("response-secret", conditionMessage(error)))
  })
  expect_length(requests, 7L)
})

test_that("libSQL follows selected accounts and rejects late or cross-session results", {
  selected <- NULL
  end <- function() NULL
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    end()
    libsql_test_response()
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    selected <<- shiny::reactiveVal(NULL)
    api <- oauth_db_libsql_api(selected, "https://db.example")
    expect_error(api$query("SELECT 42"), class = "shiny.silent.error")
    expect_length(requests, 0L)
    selected(a$connection)
    api$query("SELECT 42")
    selected(b$connection)
    api$query("SELECT 42")
    end <<- function() selected(a$connection)
    expect_error(
      api$query("SELECT 42"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    end <<- function() a$status("insufficient_scope")
    expect_error(
      api$query("SELECT 42"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    a$status("active")
    end <<- function() selected(NULL)
    expect_error(
      api$query("SELECT 42"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    retained <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      retained$query("SELECT 42"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
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
      "Bearer fixture-B",
      "Bearer fixture-B",
      "Bearer fixture-A",
      "Bearer fixture-A"
    )
  )
})

test_that("libSQL rejects invalid parameters before requesting a credential", {
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    libsql_test_response()
  })
  for (url in c(
    "http://db.example",
    "libsql://user:pass@db.example",
    "https://db.example?token=x",
    "https://db.example/#fragment",
    "https://db.example/%2e%2e/other"
  )) {
    expect_error(
      oauth_db_libsql_api(NULL, url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_libsql_api(auth$connection, "https://db.example")
    cases <- list(
      1,
      list(a = 1, 2),
      stats::setNames(list(1, 2), c("a", "a")),
      list("bad name" = 1),
      list(1:2),
      list(list(1)),
      list(factor("a")),
      list(Sys.Date()),
      list(1 + 1i),
      list(Inf),
      list(NaN),
      list(I("9223372036854775808")),
      list(I("-9223372036854775809")),
      list(I("1.5"))
    )
    for (parameters in cases) {
      expect_error(
        api$query("SELECT ?", parameters),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(api$query(""), class = "shinyOAuthDB_invalid_configuration")
    expect_error(
      api$query("SELECT 1", raw = NA),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_identical(requests, 0L)
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("libSQL validates Hrana envelopes, rows, values and metadata before returning them", {
  payload <- libsql_test_response()
  httr2::local_mocked_responses(function(req) payload)
  odb_test_domain(function(session) {
    api <- oauth_db_libsql_api(
      odb_test_authorization(session)$connection,
      "https://db.example"
    )
    mutations <- list(
      function(x) {
        x$baton <- "stream-secret"
        x
      },
      function(x) {
        x$baton <- NULL
        x["baton"] <- NULL
        x
      },
      function(x) {
        x$results <- list()
        x
      },
      function(x) {
        x$results[[2L]]$response$type <- "execute"
        x
      },
      function(x) {
        x$results[[1L]]$response$result$rows <- list(list())
        x
      },
      function(x) {
        x$results[[1L]]$response$result$cols <- list(list(name = 1))
        x
      },
      function(x) {
        x$results[[1L]]$response$result$affected_row_count <- -1
        x
      },
      function(x) {
        x$results[[
          1L
        ]]$response$result$last_insert_rowid <- "9223372036854775808"
        x
      }
    )
    for (mutate in mutations) {
      payload <<- libsql_test_response(modify = mutate)
      expect_error(
        api$query("SELECT 42", raw = TRUE),
        class = "shinyOAuthDB_invalid_response"
      )
    }
    for (cell in list(
      list(type = "integer", value = "9223372036854775808"),
      list(type = "integer", value = 42),
      list(type = "float", value = "1.5"),
      list(type = "text", value = list("a")),
      list(type = "blob", base64 = "?invalid"),
      list(type = "unknown", value = "response-secret")
    )) {
      payload <<- libsql_test_response(libsql_test_result(
        rows = list(list(cell))
      ))
      error <- expect_error(
        api$query("SELECT 42"),
        class = "shinyOAuthDB_invalid_response"
      )
      expect_false(grepl("response-secret", conditionMessage(error)))
    }
    payload <<- odb_http_response("not-json")
    expect_error(
      api$query("SELECT 42"),
      class = "shinyOAuthDB_invalid_response"
    )
  })
})
