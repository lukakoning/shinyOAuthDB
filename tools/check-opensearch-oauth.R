# Real OpenSearch Security authentication, DLS/FLS and SQL over verified TLS.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
# The fixture CA is disposable and must not be installed in the Windows store.
if (.Platform$OS.type == "windows" && !nzchar(Sys.getenv("CURL_SSL_BACKEND"))) {
  Sys.setenv(CURL_SSL_BACKEND = "openssl")
}
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_opensearch_oauth <- function() {
  docker <- function(args, check = TRUE) {
    log <- tempfile("opensearch-docker-", fileext = ".log")
    on.exit(unlink(log), add = TRUE)
    result <- processx::run("docker", args, stdout = log, stderr = "2>&1", error_on_status = FALSE)
    output <- readLines(log, warn = FALSE)
    if (check && result$status != 0L) stop(paste(output, collapse = "\n"), call. = FALSE)
    invisible(result$status)
  }
  fixture <- tempfile("shinyOAuthDB-opensearch-")
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/")
  stopifnot(startsWith(fixture, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  project <- paste0("oauthdb-opensearch-", Sys.getpid(), "-", sample.int(1e6, 1L))
  image <- "shinyoauthdb-opensearch-fixture:1"
  server_image <- Sys.getenv("OAUTHDB_OPENSEARCH_TEST_IMAGE", "opensearchproject/opensearch:3.9.0")
  docker(c("build", "--provenance=false", "-t", image, "integration/opensearch-oauth"))
  docker(c("run", "--rm", "--mount", paste0("type=bind,source=", fixture, ",target=/out"), image))
  docker(c("network", "create", project))
  on.exit(docker(c("network", "rm", project), check = FALSE), add = TRUE, after = FALSE)
  port <- as.integer(Sys.getenv("OAUTHDB_OPENSEARCH_TEST_PORT", as.character(httpuv::randomPort())))
  docker(c("run", "-d", "--name", project, "--network", project, "--network-alias", "opensearch",
    "-p", paste0("127.0.0.1:", port, ":9200"),
    "-e", "DISABLE_INSTALL_DEMO_CONFIG=true", "-e", "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m",
    "--mount", paste0("type=bind,source=", fixture, ",target=/usr/share/opensearch/config/fixture,readonly"),
    "--mount", paste0("type=bind,source=", fixture, "/opensearch.yml,target=/usr/share/opensearch/config/opensearch.yml,readonly"),
    "--mount", paste0("type=bind,source=", fixture, "/security,target=/usr/share/opensearch/config/opensearch-security,readonly"),
    server_image))
  on.exit({
    dir.create(".validation", showWarnings = FALSE)
    processx::run("docker", c("logs", project), stdout = ".validation/opensearch-oauth-server.log",
      stderr = "2>&1", error_on_status = FALSE)
    docker(c("rm", "-f", project), check = FALSE)
  }, add = TRUE, after = FALSE)
  docker(c("run", "--rm", "--network", project, "--mount",
    paste0("type=bind,source=", fixture, ",target=/out,readonly"), "--entrypoint", "python", image, "/seed.py"))
  tokens <- jsonlite::read_json(file.path(fixture, "tokens.json"))
  url <- paste0("https://localhost:", port)
  ca <- file.path(fixture, "ca.pem")
  saved <- NULL
  test_that("OpenSearch enforces visitor identities, native permissions and TLS", {
    odb_test_domain(function(session) {
      a <- NULL
      a <- odb_test_authorization(session, scopes = "search.read", refresh_token = "fixture-refresh", acquire = function(...) {
        a$token(a$make_token(tokens$alice))
        TRUE
      })
      b <- odb_test_authorization(session, id = "B", scopes = "search.read")
      writer <- odb_test_authorization(session, id = "writer", scopes = "search.read")
      a$token(a$make_token(tokens$alice))
      b$token(b$make_token(tokens$bob))
      writer$token(writer$make_token(tokens$writer))
      selected <- shiny::reactiveVal(NULL)
      api <- oauth_db_opensearch_api(selected, url, ca_bundle = ca, required_scopes = "search.read")
      expect_error(api$search("orders"), class = "shiny.silent.error")
      selected(a$connection)
      result <- api$search("orders*", query = list(track_total_hits = TRUE))
      expect_identical(result$hits$hits[[1L]]$`_source`$owner, "alice")
      expect_null(result$hits$hits[[1L]]$`_source`$secret)
      expect_identical(result$hits$hits[[1L]]$`_source`$big_id, "9007199254740993")
      expect_equal(result$hits$total$value, 1)
      aggregations <- api$search("orders", list(size = 0L,
        aggs = list(countries = list(terms = list(field = "country")))))
      expect_equal(aggregations$aggregations$countries$buckets[[1L]]$doc_count, 1)
      sql <- api$sql("SELECT owner, total FROM orders WHERE country = ?",
        list(list(type = "keyword", value = "NL")))
      expect_identical(sql$datarows[[1L]][[1L]], "alice")
      expect_equal(sql$datarows[[1L]][[2L]], 42)
      expect_error(api$sql("SELECT secret FROM orders"), class = "shinyOAuthDB_request_failed")
      expect_error(api$search("private-orders"), class = "shinyOAuthDB_request_failed")
      failure <- expect_error(api$request(c("orders", "_doc", "attempt"), "PUT", body = list(total = 1)),
        class = "shinyOAuthDB_request_failed")
      expect_identical(failure$status, 403L)
      selected(b$connection)
      expect_identical(api$search("orders")$hits$hits[[1L]]$`_source`$owner, "bob")
      expect_identical(api$sql("SELECT owner FROM orders")$datarows[[1L]][[1L]], "bob")
      selected(a$connection)
      a$token(a$make_token(tokens$expired))
      expect_error(api$search("orders"), class = "shinyOAuthDB_request_failed")
      expect_identical(a$calls$acquire, 0L)
      expect_identical(api$request(c("_plugins", "_security", "authinfo"))$user_name, "alice")
      expect_identical(a$calls$acquire, 1L)
      for (bad in list(tokens$audience, tokens$issuer, tokens$expired, paste0(tokens$alice, "invalid"), tokens$denied)) {
        a$token(a$make_token(bad))
        failure <- expect_error(api$search("orders"), class = "shinyOAuthDB_request_failed")
        expect_false(grepl(bad, conditionMessage(failure), fixed = TRUE))
      }
      selected(writer$connection)
      expect_identical(api$request(c("orders", "_doc", "written"), "PUT",
        body = list(owner = "writer", country = "NL", total = 1), query = list(refresh = TRUE))$result, "created")
      selected(a$connection)
      a$token(a$make_token(tokens$alice))
      expect_equal(api$search("orders")$hits$total$value, 1)
      a$token(a$make_token(tokens$alice, permissions = character()))
      expect_error(api$search("orders"), class = "shiny.silent.error")
      selected(NULL)
      expect_error(api$search("orders"), class = "shiny.silent.error")
      saved <<- api
      untrusted <- oauth_db_opensearch_api(b$connection, url)
      expect_error(untrusted$search("orders"), class = "shinyOAuthDB_request_failed")
      wrong_host <- oauth_db_opensearch_api(b$connection, sub("localhost", "127.0.0.1", url), ca_bundle = ca)
      expect_error(wrong_host$search("orders"), class = "shinyOAuthDB_request_failed")
    })
    odb_test_domain(function(session) {
      expect_error(saved$search("orders"), class = "shinyOAuthDB_authorization_unavailable")
    })
  })
  cat("OpenSearch JWT, DLS/FLS, SQL and TLS checks passed.\n")
}

check_opensearch_oauth()
