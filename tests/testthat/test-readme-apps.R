readme_example <- function(title) {
  if (title == "Packaged PostgreSQL") {
    return(parse(
      system.file(
        "examples",
        "postgres",
        "example.R",
        package = "shinyOAuthDB"
      ),
      keep.source = FALSE
    ))
  }
  guide <- c(
    PostgREST = "postgrest",
    StarRocks = "starrocks",
    ClickHouse = "clickhouse"
  )
  path <- if (title == "Self-hosted PostgreSQL") {
    test_path("..", "..", "README.md")
  } else {
    test_path("..", "..", "vignettes", paste0(guide[[title]], ".Rmd"))
  }
  skip_if_not(file.exists(path), "README source is unavailable")
  lines <- readLines(path, encoding = "UTF-8")
  start <- which(
    lines ==
      if (title == "Self-hosted PostgreSQL") {
        "## Example usage with PostgreSQL"
      } else {
        "## Complete Shiny app"
      }
  )
  stopifnot(length(start) == 1L)
  following <- which(seq_along(lines) > start & grepl("^## ", lines))
  end <- if (length(following)) following[[1L]] - 1L else length(lines)
  section <- lines[seq.int(start, end)]
  fences <- grep("^```", section)
  for (i in seq.int(1L, length(fences), by = 2L)) {
    code <- section[seq.int(fences[[i]] + 1L, fences[[i + 1L]] - 1L)]
    if ("library(shiny)" %in% code) {
      return(parse(text = code, keep.source = FALSE))
    }
  }
  stop("No complete Shiny app in README section: ", title)
}

for (title in c(
  "Self-hosted PostgreSQL",
  "Packaged PostgreSQL",
  "PostgREST",
  "StarRocks",
  "ClickHouse"
)) {
  local({
    source_name <- title
    test_that(
      paste("the documented", source_name, "app follows the visitor's login"),
      {
        skip_if_not_installed("RSQLite")
        if (source_name == "StarRocks") {
          skip_if_not_installed("odbc")
        }
        withr::local_envvar(playground_env())
        local_mocked_bindings(
          oauth_provider_oidc_discover = function(
            issuer,
            token_auth_style = "header",
            ...
          ) {
            shinyOAuth::oauth_provider(
              name = "readme",
              issuer = issuer,
              auth_url = paste0(issuer, "/authorize"),
              token_url = paste0(issuer, "/token"),
              jwks_uri = paste0(issuer, "/jwks"),
              id_token_validation = TRUE,
              token_auth_style = token_auth_style
            )
          },
          .package = "shinyOAuth"
        )
        local_mocked_bindings(oauth_db_demo = function(database, action) {
          expect_identical(database, "postgrest")
          expect_identical(action, "services")
          list(
            provider = shinyOAuth::oauth_provider_oidc_discover(
              "https://localhost:18443/realms/shinyoauthdb"
            ),
            url = "https://localhost:19444",
            stop = function() invisible(NULL)
          )
        })
        opened <- list()
        users <- character()
        requests <- list()
        native <- function(token, user, ...) {
          users <<- c(users, user)
          con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          attr(con, "readme_user") <- user
          opened[[length(opened) + 1L]] <<- con
          con
        }
        local_mocked_bindings(
          .odb_postgres_runtime = function() TRUE,
          .odb_postgres_connection_valid = DBI::dbIsValid,
          .odb_postgres_connect_bearer = native,
          .odb_backend_starrocks = function(token, user, ...) {
            native(token(), user())
          }
        )
        local_mocked_bindings(
          dbGetQuery = function(conn, statement, ...) {
            data.frame(database_user = attr(conn, "readme_user"))
          },
          .package = "DBI"
        )
        httr2::local_mocked_responses(function(req) {
          requests[[length(requests) + 1L]] <<- req
          user <- sub(
            "^Bearer fixture-",
            "",
            httr2::req_get_headers(req, redacted = "reveal")$Authorization
          )
          body <- if (
            source_name %in%
              c("Self-hosted PostgreSQL", "Packaged PostgreSQL", "PostgREST")
          ) {
            list(list(database_user = user))
          } else {
            list(
              meta = list(list(name = "database_user", type = "String")),
              data = list(list(user)),
              rows = 1L
            )
          }
          odb_http_response(as.character(jsonlite::toJSON(
            body,
            auto_unbox = TRUE
          )))
        })
        envir <- new.env(parent = globalenv())
        envir$runApp <- function(app, port, launch.browser, ...) {
          expect_identical(
            port,
            if (
              source_name %in%
                c("Self-hosted PostgreSQL", "Packaged PostgreSQL")
            ) {
              18100
            } else {
              8100
            }
          )
          expect_false(launch.browser)
          app
        }
        app <- eval(readme_example(source_name), envir)
        expect_s3_class(app, "shiny.appobj")
        expect_match(
          envir$ui(playground_request())$content,
          'id="rows"',
          fixed = TRUE
        )
        actions <- new.env(parent = emptyenv())
        actions$login <- 0L
        envir$oauth_module_server <- function(...) {
          module <- playground_module(actions)(...)
          module$logout()
          result <- list2env(module)
          makeActiveBinding(
            "token",
            function(value) {
              reference <- shiny::req(module$connection())
              user <- reference$identity(
                claims = "preferred_username"
              )$id_token_claims$preferred_username
              shinyOAuth::OAuthToken(
                access_token = paste0("fixture-", user),
                userinfo = list(preferred_username = user)
              )
            },
            result
          )
          result
        }
        shiny::testServer(envir$server, {
          session$flushReact()
          expect_error(output$rows, class = "shiny.silent.error")
          expect_length(opened, 0L)
          expect_length(requests, 0L)
          actions$select("A")
          session$flushReact()
          expect_match(output$rows, "\\bA\\b")
          actions$select("B")
          session$flushReact()
          expect_match(output$rows, "\\bB\\b")
          expect_false(grepl("\\bA\\b", output$rows))
          session$setInputs(logout = 1L)
          expect_error(output$rows, class = "shiny.silent.error")
        })
        if (source_name == "StarRocks") {
          expect_identical(users, c("A", "B"))
          expect_true(all(vapply(
            opened,
            function(con) !DBI::dbIsValid(con),
            logical(1)
          )))
        } else {
          expect_identical(
            vapply(
              requests,
              function(req) {
                httr2::req_get_headers(req, redacted = "reveal")$Authorization
              },
              ""
            ),
            c("Bearer fixture-A", "Bearer fixture-B")
          )
        }
      }
    )
  })
}
