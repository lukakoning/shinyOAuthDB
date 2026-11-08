# Run the packaged README app in local R against real Docker services.
# Rscript --vanilla tools/check-readme-demo.R [additional-library-paths]
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}

check_readme_demo <- function() {
  output <- file.path(
    normalizePath(".validation", winslash = "/"),
    "readme-demo"
  )
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  library <- tempfile("readme-demo-library-")
  dir.create(library)
  pkgbuild::rcmd_build_tools("INSTALL", c(paste0("--library=", library), "."))
  libpath <- c(library, .libPaths())
  path <- tempfile("README services with spaces-")
  process <- callr::r_bg(
    function(path) {
      setwd(tempdir())
      previous <- options()[c(
        "shinyOAuth.allowed_hosts",
        "shinyOAuth.allow_insecure_oidc_loopback"
      )]
      tls <- Sys.getenv(
        c("CURL_CA_BUNDLE", "CURL_SSL_BACKEND"),
        unset = NA_character_
      )
      envir <- new.env(parent = globalenv())
      # Use a fresh configuration; the startup function itself runs unchanged.
      envir$oauth_db_demo <- function(...) {
        shinyOAuthDB::oauth_db_demo(..., path = path)
      }
      envir$runApp <- function(app, port, launch.browser) {
        stopifnot(identical(port, 18100), identical(launch.browser, FALSE))
        # Add only a test shutdown input, leaving the real app and OAuth flow intact.
        server <- envir$server
        app$serverFuncSource <- function() {
          function(input, output, session) {
            server(input, output, session)
            shiny::observeEvent(input$check_stop, shiny::stopApp())
          }
        }
        shiny::runApp(
          app,
          port = port,
          launch.browser = launch.browser,
          host = "127.0.0.1"
        )
      }
      source(
        system.file(
          "examples",
          "postgres",
          "example.R",
          package = "shinyOAuthDB"
        ),
        local = envir
      )
      stopifnot(
        identical(options()[names(previous)], previous),
        identical(Sys.getenv(names(tls), unset = NA_character_), tls)
      )
      project <- paste0(
        "shinyoauthdb-demo-postgrest-",
        substr(
          openssl::sha256(charToRaw(normalizePath(path, winslash = "/"))),
          1L,
          8L
        )
      )
      containers <- system2(
        Sys.which("docker"),
        vapply(
          c(
            "ps",
            "-a",
            "--quiet",
            "--filter",
            paste0("label=com.docker.compose.project=", project)
          ),
          shQuote,
          ""
        ),
        stdout = TRUE
      )
      stopifnot(!length(containers))
      # These checks run before R exits, so an exit finalizer cannot hide missing onStop cleanup.
      TRUE
    },
    args = list(path),
    libpath = libpath,
    supervise = TRUE,
    stdout = file.path(output, "app.log"),
    stderr = file.path(output, "docker.log")
  )
  chrome <- NULL
  on.exit(
    {
      if (!is.null(chrome)) {
        chrome$close()
      }
      if (process$is_alive()) {
        try(
          callr::r(
            function(path) {
              shinyOAuthDB::oauth_db_demo(
                "postgrest",
                app = "local",
                action = "stop",
                path = path
              )
            },
            args = list(path),
            libpath = libpath
          ),
          silent = TRUE
        )
        process$kill()
      }
    },
    add = TRUE
  )
  deadline <- Sys.time() + 900
  repeat {
    ready <- tryCatch(
      curl::curl_fetch_memory("http://localhost:18100")$status_code == 200L,
      error = function(e) FALSE
    )
    if (ready) {
      break
    }
    if (!process$is_alive() || Sys.time() > deadline) {
      stop("README app failed to start; see ", output)
    }
    Sys.sleep(0.2)
  }
  chrome <- chromote::Chromote$new()
  value <- function(browser, js) {
    browser$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  }
  wait <- function(browser, js) {
    deadline <- Sys.time() + 40
    repeat {
      if (isTRUE(tryCatch(value(browser, js), error = function(e) FALSE))) {
        return(invisible(TRUE))
      }
      if (Sys.time() > deadline) {
        stop(
          "Browser timed out: ",
          js,
          "; ",
          value(browser, "document.body.innerText.slice(0, 1200)")
        )
      }
      Sys.sleep(0.1)
    }
  }
  for (user in c("alice", "bob")) {
    context <- chrome$Target$createBrowserContext()$browserContextId
    target <- chrome$Target$createTarget(
      "about:blank",
      browserContextId = context
    )$targetId
    browser <- chromote::ChromoteSession$new(parent = chrome, targetId = target)
    # Only the test browser accepts the generated local sign-in certificate.
    browser$Security$setIgnoreCertificateErrors(ignore = TRUE)
    browser$go_to("http://localhost:18100")
    wait(
      browser,
      "Boolean(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected() && document.querySelector('#login:not(:disabled)'))"
    )
    stopifnot(
      identical(
        trimws(value(browser, "document.querySelector('#rows').textContent")),
        ""
      ),
      isTRUE(value(browser, "!document.querySelector('.shiny-output-error')"))
    )
    value(browser, "document.querySelector('#login').click()")
    wait(
      browser,
      "Boolean(document.querySelector('#username') && document.querySelector('#kc-login'))"
    )
    value(
      browser,
      sprintf(
        paste0(
          "document.querySelector('#username').value='%s';",
          "document.querySelector('#password').value='%s'; document.querySelector('#kc-login').click()"
        ),
        user,
        user
      )
    )
    wait(
      browser,
      sprintf(
        "Boolean(document.querySelector('#rows')?.textContent.includes('%s-visible-1'))",
        user
      )
    )
    rows <- value(browser, "document.querySelector('#rows').textContent")
    other <- if (user == "alice") "bob" else "alice"
    stopifnot(
      grepl(paste0(user, "-visible-2"), rows),
      !grepl(paste0(other, "-visible"), rows)
    )
    value(browser, "document.querySelector('#logout').click()")
    wait(
      browser,
      "Boolean(document.querySelector('#rows') && document.querySelector('#rows').textContent.trim() === '')"
    )
    stopifnot(isTRUE(value(
      browser,
      "!document.querySelector('.shiny-output-error')"
    )))
    cat(
      user,
      ": real sign-in, PostgreSQL row permissions and sign-out passed\n",
      sep = ""
    )
    if (user == "bob") {
      value(browser, "Shiny.setInputValue('check_stop', 1)")
    }
    browser$close()
    chrome$Target$disposeBrowserContext(context)
  }
  process$wait(30000)
  stopifnot(!process$is_alive(), isTRUE(process$get_result()))
  jsonlite::write_json(
    list(
      installed_package = TRUE,
      local_R = TRUE,
      real_oauth = TRUE,
      real_postgres = TRUE,
      isolated_rows = TRUE,
      sign_out = TRUE,
      onStop_cleanup = TRUE,
      R_options_restored = TRUE,
      TLS_settings_unchanged = TRUE
    ),
    file.path(output, "result.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("README app: installed-package Docker/browser check passed.\n")
}
dir.create(".validation", showWarnings = FALSE)
check_readme_demo()
