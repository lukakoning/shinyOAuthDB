test_that("generated authorization sequences agree with a connection ownership model", {
  skip_if_not_installed("RSQLite")
  for (seed in c(7, 31, 97)) {
    odb_test_domain(function(session) {
      grants <- list(
        A = odb_test_authorization(session, "A"),
        B = odb_test_authorization(session, "B")
      )
      selected <- shiny::reactiveVal(NULL)
      handles <- list()
      opened <- cleaned <- 0L
      con <- oauth_db_connect(
        selected,
        required_scopes = "read",
        connect = function(token) {
          opened <<- opened + 1L
          native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          DBI::dbWriteTable(native, "identity", data.frame(token = token))
          handles[[length(handles) + 1L]] <<- native
          native
        },
        disconnect = function(native) {
          cleaned <<- cleaned + 1L
          if (DBI::dbIsValid(native)) DBI::dbDisconnect(native)
        }
      )
      read <- function() {
        native <- con()
        DBI::dbReadTable(native, "identity")$token
      }
      rows <- shiny::reactive(read())
      owner <- current_handle <- NULL
      allowed <- c(A = TRUE, B = TRUE)
      credentials <- c(A = "fixture-A", B = "fixture-B")
      expected_opened <- expected_cleaned <- 0L
      expected_value <- NULL
      retire <- function() {
        if (!is.null(current_handle)) {
          expected_cleaned <<- expected_cleaned + 1L
        }
        current_handle <<- expected_value <<- NULL
      }
      actions <- c(
        "A",
        "rotateA",
        "denyA",
        "restoreA",
        "B",
        "logout",
        "A",
        "break",
        "query"
      )
      state <- seed
      choices <- c(
        "A",
        "B",
        "logout",
        "rotateA",
        "rotateB",
        "denyA",
        "denyB",
        "restoreA",
        "restoreB",
        "query"
      )
      for (i in seq_len(40L)) {
        state <- (state * 48271) %% 2147483647
        actions <- c(
          actions,
          choices[[as.integer(state %% length(choices)) + 1L]]
        )
      }
      for (step in seq_along(actions)) {
        action <- actions[[step]]
        info <- paste("seed", seed, "step", step, action)
        if (action %in% c("A", "B", "logout")) {
          next_owner <- if (action == "logout") NULL else action
          if (!identical(next_owner, owner)) {
            retire()
          }
          owner <- next_owner
          selected(if (is.null(owner)) NULL else grants[[owner]]$connection)
        } else if (action == "break") {
          if (!is.null(current_handle)) {
            DBI::dbDisconnect(current_handle)
            retire()
          }
          # Explicit invalidation needs an input event to rerun a cached query.
          rows <- shiny::reactive(read())
        } else if (action != "query") {
          id <- substr(action, nchar(action), nchar(action))
          if (startsWith(action, "rotate")) {
            credentials[[id]] <- paste0("rotated-", id, "-", step)
          }
          if (startsWith(action, "deny")) {
            allowed[[id]] <- FALSE
          }
          if (startsWith(action, "restore")) {
            allowed[[id]] <- TRUE
          }
          grants[[id]]$token(grants[[id]]$make_token(
            credentials[[id]],
            permissions = if (allowed[[id]]) c("read", "write") else "write"
          ))
          if (identical(owner, id) && !allowed[[id]]) retire()
        }
        session$flushReact()
        if (is.null(owner) || !allowed[[owner]]) {
          expect_error(rows(), class = "shiny.silent.error", info = info)
        } else {
          if (is.null(current_handle)) {
            expected_opened <- expected_opened + 1L
            expected_value <- unname(credentials[[owner]])
          }
          expect_identical(rows(), expected_value, info = info)
          current_handle <- con()
        }
        expect_identical(
          c(opened, cleaned),
          c(expected_opened, expected_cleaned),
          info = info
        )
        live <- vapply(handles, DBI::dbIsValid, logical(1))
        expect_identical(
          sum(live),
          as.integer(!is.null(current_handle)),
          info = info
        )
        if (any(live)) {
          expect_identical(handles[[which(live)]], current_handle, info = info)
        }
      }
      retire()
      session$close()
      expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
      expect_false(any(vapply(handles, DBI::dbIsValid, logical(1))))
      expect_identical(cleaned, expected_cleaned)
    })
  }
})

test_that("NULL connectors fail without caching a handle and can recover", {
  odb_test_domain(function(session) {
    grant <- odb_test_authorization(session)
    ready <- FALSE
    opened <- cleaned <- 0L
    con <- oauth_db_connect(
      grant$connection,
      connect = function(token) {
        opened <<- opened + 1L
        if (ready) list(token = token) else NULL
      },
      disconnect = function(native) cleaned <<- cleaned + 1L
    )
    expect_error(
      con(),
      "connector must return",
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_identical(cleaned, 0L)
    ready <- TRUE
    expect_identical(con()$token, "fixture-A")
    expect_identical(con()$token, "fixture-A")
    expect_identical(opened, 2L)
    session$close()
    expect_identical(cleaned, 1L)
  })
})

test_that("invalid lifecycle callbacks fail before credential acquisition", {
  odb_test_domain(function(session) {
    reads <- 0L
    grant <- list(
      id = "A",
      has_scopes = function(...) TRUE,
      access_token = function(...) {
        reads <<- reads + 1L
        "fixture-token"
      }
    )
    expect_error(
      oauth_db_connect(grant, connect = FALSE),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      oauth_db_connect(grant, disconnect = FALSE),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      .odb_bind(grant, connect = identity, is_valid = FALSE),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_identical(reads, 0L)
  })
})
