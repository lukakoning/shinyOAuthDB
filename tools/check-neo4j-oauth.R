# Native Neo4j OIDC authentication and graph privileges over verified HTTPS.
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

check_neo4j_oauth <- function() {
  docker <- function(args, check = TRUE) {
    result <- processx::run("docker", args, error_on_status = FALSE)
    if (check && result$status != 0L) {
      stop(paste(result$stdout, result$stderr, sep = "\n"), call. = FALSE)
    }
    invisible(result$status)
  }
  fixture <- tempfile("shinyOAuthDB-neo4j-")
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/")
  stopifnot(startsWith(
    fixture,
    paste0(normalizePath(tempdir(), winslash = "/"), "/")
  ))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  project <- paste0("oauthdb-neo4j-", Sys.getpid(), "-", sample.int(1e6, 1L))
  issuer <- paste0(project, "-issuer")
  image <- "shinyoauthdb-neo4j-fixture:1"
  server_image <- Sys.getenv(
    "OAUTHDB_NEO4J_TEST_IMAGE",
    "neo4j:5.26.32-enterprise"
  )
  docker(c(
    "build",
    "--provenance=false",
    "-t",
    image,
    "integration/neo4j-oauth"
  ))
  mount <- paste0("type=bind,source=", fixture, ",target=/out")
  docker(c("run", "--rm", "--mount", mount, image, "prepare"))
  docker(c("network", "create", project))
  on.exit(
    docker(c("network", "rm", project), check = FALSE),
    add = TRUE,
    after = FALSE
  )
  docker(c(
    "run",
    "-d",
    "--name",
    issuer,
    "--network",
    project,
    "--network-alias",
    "issuer",
    "--mount",
    paste0(mount, ",readonly"),
    image,
    "serve"
  ))
  on.exit(
    docker(c("rm", "-f", issuer), check = FALSE),
    add = TRUE,
    after = FALSE
  )
  port <- as.integer(Sys.getenv(
    "OAUTHDB_NEO4J_TEST_PORT",
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
    "neo4j",
    "-p",
    paste0("127.0.0.1:", port, ":7473"),
    "-e",
    "NEO4J_ACCEPT_LICENSE_AGREEMENT=eval",
    "-e",
    "NEO4J_AUTH=neo4j/fixture-admin-password",
    "-e",
    "JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=/tmp/fixture.p12 -Djavax.net.ssl.trustStorePassword=changeit",
    "--mount",
    paste0("type=bind,source=", fixture, ",target=/fixture,readonly"),
    "--mount",
    paste0("type=bind,source=", fixture, "/neo4j.conf,target=/conf/neo4j.conf"),
    "--entrypoint",
    "bash",
    server_image,
    "-c",
    paste(
      "keytool -importcert -noprompt -alias fixture -file /fixture/ca.pem",
      "-keystore /tmp/fixture.p12 -storepass changeit && exec /startup/docker-entrypoint.sh neo4j"
    )
  ))
  on.exit(
    {
      dir.create(".validation", showWarnings = FALSE)
      processx::run(
        "docker",
        c("logs", project),
        stdout = ".validation/neo4j-oauth-server.log",
        stderr = "2>&1",
        error_on_status = FALSE
      )
      docker(
        c(
          "cp",
          paste0(project, ":/logs/debug.log"),
          ".validation/neo4j-oauth-debug.log"
        ),
        check = FALSE
      )
      docker(c("rm", "-f", "-v", project), check = FALSE)
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
    paste0(mount, ",readonly"),
    image,
    "seed"
  ))
  tokens <- jsonlite::read_json(file.path(fixture, "tokens.json"))
  url <- paste0("https://localhost:", port)
  ca <- file.path(fixture, "ca.pem")
  test_that("Neo4j validates JWTs, applies graph privileges and runs real Query API requests", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, scopes = "graph.read")
      auth$token(auth$make_token(tokens$alice))
      graph <- oauth_db_neo4j_api(
        auth$connection,
        url,
        ca_bundle = ca,
        required_scopes = "graph.read"
      )
      expect_identical(
        graph$query("SHOW CURRENT USER YIELD user RETURN user")$user,
        "alice"
      )
      expect_identical(
        graph$query("MATCH (n) RETURN n.name AS name")$name,
        "Alice"
      )
      expect_identical(
        graph$query("MATCH (n) RETURN n.id AS id")$id,
        "9007199254740993"
      )
      expect_identical(
        graph$query(
          "MATCH (n) WHERE n.name = $name RETURN n.name AS name",
          list(name = "Alice")
        )$name,
        "Alice"
      )
      expect_equal(
        nrow(graph$query(
          "MATCH (n) WHERE n.name = $name RETURN n.name",
          list(name = "Alice' OR true //")
        )),
        0L
      )
      expect_identical(
        graph$query("MATCH (n) RETURN n")$n[[1L]]$properties$name,
        "Alice"
      )
      expect_error(
        graph$execute("CREATE (:AliceData {name:'denied'})"),
        class = "shinyOAuthDB_error"
      )
      expect_error(
        graph$query("THIS IS NOT CYPHER", raw = TRUE),
        class = "shinyOAuthDB_error"
      )
      cat("Checking a second visitor's identity and graph privileges.\n")
      auth$token(auth$make_token(tokens$bob))
      expect_identical(
        graph$query("SHOW CURRENT USER YIELD user RETURN user")$user,
        "bob"
      )
      expect_identical(
        graph$query("MATCH (n) RETURN n.name AS name")$name,
        "Bob"
      )
      auth$token(auth$make_token(tokens$renewed))
      expect_identical(
        graph$query("SHOW CURRENT USER YIELD user RETURN user")$user,
        "alice"
      )
      cat("Checking JWT rejection, writes and TLS verification.\n")
      for (bad in tokens[c("audience", "issuer", "expired", "signature")]) {
        auth$token(auth$make_token(bad))
        error <- expect_error(
          graph$query("RETURN 1"),
          class = "shinyOAuthDB_request_failed"
        )
        expect_identical(error$status, 401L)
        expect_false(grepl(bad, conditionMessage(error), fixed = TRUE))
      }
      auth$token(auth$make_token(tokens$writer))
      counters <- graph$execute(
        "CREATE (:Written {name:$name})",
        list(name = "writer")
      )
      expect_equal(counters$nodesCreated, 1L)
      native <- graph$query(
        "MATCH p=(:AliceData)-[:KNOWS]->(:BobData) RETURN p",
        raw = TRUE
      )
      expect_length(native$data$values[[1L]][[1L]], 3L)
      expect_true(length(native$bookmarks) > 0L)
      untrusted <- oauth_db_neo4j_api(auth$connection, url)
      expect_error(
        untrusted$query("RETURN 1"),
        class = "shinyOAuthDB_request_failed"
      )
      wrong_host <- oauth_db_neo4j_api(
        auth$connection,
        sub("localhost", "127.0.0.1", url),
        ca_bundle = ca
      )
      expect_error(
        wrong_host$query("RETURN 1"),
        class = "shinyOAuthDB_request_failed"
      )
      auth$token(auth$make_token(tokens$alice, permissions = character()))
      expect_error(graph$query("RETURN 1"), class = "shiny.silent.error")
      auth$current(FALSE)
      expect_error(graph$query("RETURN 1"), class = "shiny.silent.error")
    })
  })
  cat(
    "Neo4j native JWT, graph privileges, Cypher, counters and TLS checks passed.\n"
  )
}

check_neo4j_oauth()
