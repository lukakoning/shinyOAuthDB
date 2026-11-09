# Native Elasticsearch JWT validation and per-user permissions over verified TLS.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
if (.Platform$OS.type == "windows" && !nzchar(Sys.getenv("CURL_SSL_BACKEND"))) {
  Sys.setenv(CURL_SSL_BACKEND = "openssl")
}
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_elasticsearch_oauth <- function() {
  docker <- function(args, check = TRUE) {
    result <- processx::run("docker", args, error_on_status = FALSE)
    if (check && result$status != 0L) {
      stop(paste(result$stdout, result$stderr, sep = "\n"), call. = FALSE)
    }
    invisible(result$status)
  }
  fixture <- tempfile("shinyOAuthDB-elasticsearch-")
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/")
  stopifnot(startsWith(
    fixture,
    paste0(normalizePath(tempdir(), winslash = "/"), "/")
  ))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  project <- paste0(
    "oauthdb-elasticsearch-",
    Sys.getpid(),
    "-",
    sample.int(1e6, 1L)
  )
  image <- "shinyoauthdb-elasticsearch-fixture:1"
  server_image <- Sys.getenv(
    "OAUTHDB_ELASTICSEARCH_TEST_IMAGE",
    "docker.elastic.co/elasticsearch/elasticsearch:9.2.0"
  )
  docker(c(
    "build",
    "--provenance=false",
    "-t",
    image,
    "integration/elasticsearch-oauth"
  ))
  docker(c(
    "run",
    "--rm",
    "--mount",
    paste0("type=bind,source=", fixture, ",target=/out"),
    image
  ))
  docker(c("network", "create", project))
  on.exit(
    docker(c("network", "rm", project), check = FALSE),
    add = TRUE,
    after = FALSE
  )
  port <- as.integer(Sys.getenv(
    "OAUTHDB_ELASTICSEARCH_TEST_PORT",
    as.character(httpuv::randomPort())
  ))
  docker(c(
    "run",
    "-d",
    "--name",
    project,
    "--network",
    project,
    "--network-alias",
    "elasticsearch",
    "-p",
    paste0("127.0.0.1:", port, ":9200"),
    "-e",
    "ES_JAVA_OPTS=-Xms512m -Xmx512m",
    "-e",
    "ELASTIC_PASSWORD=fixture-admin-password",
    "--mount",
    paste0(
      "type=bind,source=",
      fixture,
      ",target=/usr/share/elasticsearch/config/fixture,readonly"
    ),
    "--mount",
    paste0(
      "type=bind,source=",
      fixture,
      "/elasticsearch.yml,target=/usr/share/elasticsearch/config/elasticsearch.yml,readonly"
    ),
    "--entrypoint",
    "bash",
    server_image,
    "-c",
    paste(
      "bin/elasticsearch-keystore create &&",
      "printf '%s' 'fixture-realm-secret' | bin/elasticsearch-keystore add -x",
      "xpack.security.authc.realms.jwt.visitors.client_authentication.shared_secret",
      "&& exec /usr/local/bin/docker-entrypoint.sh elasticsearch"
    )
  ))
  on.exit(
    {
      dir.create(".validation", showWarnings = FALSE)
      processx::run(
        "docker",
        c("logs", project),
        stdout = ".validation/elasticsearch-oauth-server.log",
        stderr = "2>&1",
        error_on_status = FALSE
      )
      docker(c("rm", "-f", project), check = FALSE)
    },
    add = TRUE,
    after = FALSE
  )
  docker(c(
    "run",
    "--rm",
    "--network",
    project,
    "--mount",
    paste0("type=bind,source=", fixture, ",target=/out,readonly"),
    "--entrypoint",
    "python",
    image,
    "/seed.py"
  ))
  tokens <- jsonlite::read_json(file.path(fixture, "tokens.json"))
  url <- paste0("https://localhost:", port)
  ca <- file.path(fixture, "ca.pem")
  saved <- NULL
  test_that("Elasticsearch JWT roles enforce visitor identity, DLS/FLS, SQL and ES|QL", {
    odb_test_domain(function(session) {
      a <- NULL
      a <- odb_test_authorization(
        session,
        scopes = "search.read",
        refresh_token = "fixture-refresh",
        acquire = function(...) {
          a$token(a$make_token(tokens$alice))
          TRUE
        }
      )
      b <- odb_test_authorization(session, id = "B", scopes = "search.read")
      a$token(a$make_token(tokens$alice))
      b$token(b$make_token(tokens$bob))
      selected <- shiny::reactiveVal(NULL)
      api <- oauth_db_elasticsearch_api(
        selected,
        url,
        "fixture-realm-secret",
        ca_bundle = ca,
        required_scopes = "search.read"
      )
      expect_error(api$search("orders"), class = "shiny.silent.error")
      selected(a$connection)
      expect_identical(
        api$request(c("_security", "_authenticate"))$username,
        "alice"
      )
      result <- api$search("orders", query = list(track_total_hits = TRUE))
      expect_identical(result$hits$hits[[1L]]$`_source`$owner, "alice")
      expect_null(result$hits$hits[[1L]]$`_source`$secret)
      expect_identical(
        result$hits$hits[[1L]]$`_source`$big_id,
        "9007199254740993"
      )
      expect_equal(result$hits$total$value, 1)
      aggregation <- api$search(
        "orders",
        list(
          size = 0L,
          aggs = list(countries = list(terms = list(field = "country")))
        )
      )
      expect_equal(
        aggregation$aggregations$countries$buckets[[1L]]$doc_count,
        1
      )
      sql <- api$sql(
        "SELECT owner, total FROM orders WHERE country = ?",
        list("NL")
      )
      expect_identical(sql$rows[[1L]][[1L]], "alice")
      expect_equal(sql$rows[[1L]][[2L]], 42)
      esql <- api$esql(
        "FROM orders | WHERE country == ? | KEEP owner, total",
        list("NL")
      )
      expect_identical(esql$values[[1L]][[1L]], "alice")
      expect_equal(esql$values[[1L]][[2L]], 42)
      expect_error(
        api$sql("SELECT secret FROM orders"),
        class = "shinyOAuthDB_request_failed"
      )
      failure <- expect_error(
        api$search("private-orders"),
        class = "shinyOAuthDB_request_failed"
      )
      expect_identical(failure$status, 403L)
      failure <- expect_error(
        api$request(
          c("orders", "_doc", "attempt"),
          "PUT",
          body = list(total = 1)
        ),
        class = "shinyOAuthDB_request_failed"
      )
      expect_identical(failure$status, 403L)
      selected(b$connection)
      expect_identical(
        api$search("orders")$hits$hits[[1L]]$`_source`$owner,
        "bob"
      )
      expect_identical(
        api$sql("SELECT owner FROM orders")$rows[[1L]][[1L]],
        "bob"
      )
      expect_identical(
        api$esql("FROM orders | KEEP owner")$values[[1L]][[1L]],
        "bob"
      )
      selected(a$connection)
      a$token(a$make_token(tokens$expired))
      expect_error(api$search("orders"), class = "shinyOAuthDB_request_failed")
      expect_identical(a$calls$acquire, 0L)
      expect_identical(
        api$request(c("_security", "_authenticate"))$username,
        "alice"
      )
      expect_identical(a$calls$acquire, 1L)
      for (bad in list(
        tokens$audience,
        tokens$issuer,
        tokens$subject,
        tokens$expired,
        paste0(tokens$alice, "invalid"),
        tokens$denied
      )) {
        a$token(a$make_token(bad))
        failure <- expect_error(
          api$search("orders"),
          class = "shinyOAuthDB_request_failed"
        )
        expect_false(grepl(bad, conditionMessage(failure), fixed = TRUE))
      }
      a$token(a$make_token(tokens$alice))
      for (secret in list(NULL, "wrong-realm-secret")) {
        other <- oauth_db_elasticsearch_api(
          a$connection,
          url,
          secret,
          ca_bundle = ca
        )
        expect_error(
          other$search("orders"),
          class = "shinyOAuthDB_request_failed"
        )
      }
      writer <- odb_test_authorization(
        session,
        id = "writer",
        scopes = "search.read"
      )
      writer$token(writer$make_token(tokens$writer))
      selected(writer$connection)
      expect_identical(
        api$request(
          c("orders", "_doc", "written"),
          "PUT",
          query = list(refresh = TRUE),
          body = list(owner = "writer", country = "NL", total = 1)
        )$result,
        "created"
      )
      selected(a$connection)
      expect_equal(api$search("orders")$hits$total$value, 1)
      a$token(a$make_token(tokens$alice, permissions = character()))
      expect_error(api$search("orders"), class = "shiny.silent.error")
      selected(NULL)
      expect_error(api$search("orders"), class = "shiny.silent.error")
      saved <<- api
      untrusted <- oauth_db_elasticsearch_api(
        b$connection,
        url,
        "fixture-realm-secret"
      )
      expect_error(
        untrusted$search("orders"),
        class = "shinyOAuthDB_request_failed"
      )
      wrong_host <- oauth_db_elasticsearch_api(
        b$connection,
        sub("localhost", "127.0.0.1", url),
        "fixture-realm-secret",
        ca_bundle = ca
      )
      expect_error(
        wrong_host$search("orders"),
        class = "shinyOAuthDB_request_failed"
      )
    })
    odb_test_domain(function(session) {
      expect_error(
        saved$search("orders"),
        class = "shinyOAuthDB_authorization_unavailable"
      )
    })
  })
  cat("Elasticsearch JWT, DLS/FLS, SQL, ES|QL and TLS checks passed.\n")
}

check_elasticsearch_oauth()
