library(shinyOAuthDB)
source(file.path("..", "..", "tests", "testthat", "helper-authorization.R"))

testthat::test_that("ClickHouse public HTTPS queries round-trip native values and enforce local user grants", {
  odb_test_domain(function(session) {
    alice <- odb_test_authorization(session, "alice")
    bob <- odb_test_authorization(session, "bob")
    selected <- shiny::reactiveVal(alice$connection)
    api <- oauth_db_clickhouse_api(
      selected,
      "https://localhost:18444",
      database = "reporting"
    )
    testthat::expect_identical(
      api$query("SELECT marker FROM rows ORDER BY id")$marker,
      paste0("alice-visible-", 1:2)
    )
    text <- "quoted ' text; -- café 雪\t\n\\"
    instant <- as.POSIXct("2020-02-29 12:34:56", tz = "UTC") + 0.125
    rows <- api$query(
      paste(
        "SELECT {text:String} AS text, {missing:Nullable(String)} AS missing,",
        "{integer:Int64} AS integer, {decimal:Decimal(30,9)} AS decimal, {day:Date} AS day,",
        "{at:DateTime64(6,'UTC')} AS instant, [1,2,3] AS array"
      ),
      parameters = list(
        text = text,
        missing = NULL,
        integer = "9223372036854775807",
        decimal = "123456789.123456789",
        day = as.Date("2020-02-29"),
        at = instant
      )
    )
    testthat::expect_identical(rows$text, text)
    testthat::expect_true(is.na(rows$missing))
    testthat::expect_identical(rows$integer, "9223372036854775807")
    testthat::expect_identical(rows$decimal, "123456789.123456789")
    testthat::expect_identical(rows$day, as.Date("2020-02-29"))
    testthat::expect_identical(rows$instant, "2020-02-29 12:34:56.125000")
    testthat::expect_identical(unlist(rows$array), c(1L, 2L, 3L))
    empty <- api$query(
      "SELECT CAST(NULL AS Nullable(String)) AS value WHERE FALSE"
    )
    testthat::expect_identical(empty, data.frame(value = character()))
    testthat::expect_error(
      api$query("SELECT unknown_fixture_function()"),
      class = "shinyOAuthDB_request_failed"
    )
    selected(bob$connection)
    session$flushReact()
    testthat::expect_identical(
      api$query("SELECT marker FROM rows ORDER BY id")$marker,
      paste0("bob-visible-", 1:2)
    )
    testthat::expect_error(
      api$execute("INSERT INTO writes VALUES ('forbidden')"),
      class = "shinyOAuthDB_request_failed"
    )
    selected(NULL)
    session$flushReact()
    testthat::expect_error(api$query("SELECT 1"), class = "shiny.silent.error")
  })
})

testthat::test_that("ClickHouse public writes execute once after dropped or delayed responses", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, "alice")
    api <- oauth_db_clickhouse_api(
      auth$connection,
      "https://localhost:18444",
      database = "reporting"
    )
    api$execute("INSERT INTO writes VALUES ('success')")
    for (fault in c("drop", "delay")) {
      # Seed curl's connection pool: a dropped response on a reused HTTP/1.1
      # connection can otherwise cause libcurl to replay the write itself.
      warm <- httr2::req_perform(httr2::request(
        "https://localhost:18444/health"
      ))
      testthat::expect_identical(httr2::resp_status(warm), 200L)
      faulty <- oauth_db_clickhouse_api(
        auth$connection,
        paste0("https://localhost:18444/", fault),
        database = "reporting",
        timeout = if (fault == "delay") 2 else 5
      )
      error <- tryCatch(
        faulty$execute(paste0("INSERT INTO writes VALUES ('", fault, "')")),
        error = identity
      )
      testthat::expect_s3_class(
        error,
        if (fault == "delay") {
          "shinyOAuthDB_timeout"
        } else {
          "shinyOAuthDB_request_failed"
        }
      )
      count <- api$query(
        "SELECT count() AS n FROM writes WHERE operation = {operation:String}",
        parameters = list(operation = fault)
      )
      testthat::expect_identical(count$n, "1")
    }
    testthat::expect_identical(
      api$query(
        "SELECT count() AS n FROM writes WHERE operation = 'success'"
      )$n,
      "1"
    )
  })
})
