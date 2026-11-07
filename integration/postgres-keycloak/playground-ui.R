# Keep the data table prominent; secondary checks have their own results.
postgres_playground_ui <- function(config) {
  button <- function(id, label, pending, primary = FALSE) {
    shiny::actionButton(
      id,
      label,
      class = if (primary) "btn-primary" else "btn-default",
      disabled = if (id != "stop_playground") "disabled" else NULL,
      `data-pending` = pending
    )
  }
  shiny::fluidPage(
    title = "PostgreSQL OAuth playground",
    lang = "en",
    shiny::tags$head(
      shiny::tags$style(shiny::HTML(
        "
        .pg-playground { max-width: 1120px; margin: 0 auto; padding: 12px 8px 40px; }
        .pg-playground h1 { font-size: 28px; margin-bottom: 12px; }
        .pg-playground h2 { font-size: 21px; margin-top: 28px; }
        .pg-actions { display: flex; flex-wrap: wrap; gap: 8px; margin: 14px 0; }
        .pg-playground .btn { min-height: 44px; white-space: normal; }
        .pg-playground .btn:focus-visible, .pg-playground summary:focus-visible {
          outline: 3px solid #185a93; outline-offset: 3px;
        }
        .pg-playground dl { margin: 12px 0 20px; }
        .pg-playground dt { margin-top: 10px; }
        .pg-playground dd, .pg-playground code { overflow-wrap: anywhere; }
        .pg-playground fieldset { border-top: 1px solid #ddd; padding: 16px 0; }
        .pg-playground legend { font-size: 17px; border: 0; margin-bottom: 4px; }
        .pg-playground summary { display: list-item; margin-left: 18px; cursor: pointer; font-weight: 600; padding: 14px 0; }
        .pg-playground .alert { margin: 14px 0; }
        .pg-playground .shiny-output-error { color: #8b1c1c; }
        #action_status { min-height: 64px; }
        #rows { overflow-x: auto; min-height: 110px; }
      "
      )),
      shiny::tags$script(shiny::HTML(
        r"(
        (() => {
          document.documentElement.lang = 'en';
          window.pgErrors = [];
          window.addEventListener('error', event => window.pgErrors.push(event.message));
          window.addEventListener('unhandledrejection', event => window.pgErrors.push(String(event.reason)));
          const actions = () => document.querySelectorAll('button[data-pending]');
          const install = () => Shiny.addCustomMessageHandler('postgres.controls', state => {
            actions().forEach(button => {
              button.disabled = !state.enabled[button.id];
              button.removeAttribute('aria-busy');
            });
            const login = document.getElementById('login');
            if (login) login.textContent = state.signed_in ? 'Switch account' : 'Sign in';
          });
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
          else install();
          window.addEventListener('click', event => {
            const button = event.target.closest('button[data-pending]');
            if (!button || button.disabled) return;
            const status = document.getElementById('action_status');
            if (status) status.textContent = button.dataset.pending;
            button.setAttribute('aria-busy', 'true');
            actions().forEach(action => {
              if (!['logout', 'stop_playground'].includes(action.id)) action.disabled = true;
            });
          });
          jQuery(document).on('shiny:disconnected', () => {
            actions().forEach(button => { button.disabled = true; });
            const status = document.getElementById('action_status');
            if (status) status.textContent = 'The app disconnected. Reload the page to reconnect.';
          });
        })();
      )"
      ))
    ),
    shiny::tags$main(
      class = "pg-playground",
      shiny::h1("PostgreSQL OAuth playground"),
      shiny::p(
        "Sign in as Alice or Bob. The same SQL runs for both accounts; PostgreSQL decides which rows each can read."
      ),
      shiny::tags$details(
        shiny::tags$summary("Local demo accounts"),
        shiny::tags$dl(
          shiny::tags$dt("Alice"),
          shiny::tags$dd(
            shiny::tags$code("alice"),
            " / ",
            shiny::tags$code("alice")
          ),
          shiny::tags$dt("Bob"),
          shiny::tags$dd(
            shiny::tags$code("bob"),
            " / ",
            shiny::tags$code("bob")
          )
        )
      ),
      shiny::div(
        class = "pg-actions",
        button("login", "Sign in", "Opening Keycloak sign-in...", TRUE),
        button(
          "logout",
          "Sign out",
          "Signing out and closing the connection..."
        ),
        if (isTRUE(config$playground)) {
          button(
            "stop_playground",
            "Stop playground",
            "Stopping the app and removing its containers..."
          )
        }
      ),
      shiny::div(
        role = "status",
        `aria-live` = "polite",
        shiny::uiOutput("action_status")
      ),
      shiny::fluidRow(
        shiny::column(
          8,
          shiny::h2("Database rows"),
          shiny::div(
            class = "pg-actions",
            button(
              "load",
              "Reload rows",
              "Reading your rows from PostgreSQL...",
              TRUE
            ),
            button(
              "refresh",
              "Refresh token",
              "Refreshing your token in the background..."
            )
          ),
          shiny::uiOutput("data_status"),
          shiny::tableOutput("rows"),
          shiny::h2("Permission checks"),
          shiny::tags$fieldset(
            shiny::tags$legend("Database role"),
            shiny::p(
              "Try to connect as the other account using your own token."
            ),
            button(
              "request_other_role",
              "Try the other role",
              "Checking whether PostgreSQL rejects the other role..."
            ),
            shiny::textOutput("role_status")
          ),
          shiny::tags$fieldset(
            shiny::tags$legend("Table access"),
            shiny::p(
              "Read your account's private table, then try the other account's table."
            ),
            button(
              "probe_table_grants",
              "Check table access",
              "Checking your table grants..."
            ),
            shiny::textOutput("grants_status")
          ),
          shiny::tags$fieldset(
            shiny::tags$legend("Token scope"),
            shiny::p(
              "Ask PostgreSQL to check this token for the required database.read scope."
            ),
            button(
              "probe_native_scope",
              "Check token scope",
              "Checking the token scope with PostgreSQL..."
            ),
            shiny::textOutput("scope_status")
          )
        ),
        shiny::column(
          4,
          shiny::h2("Current session"),
          shiny::uiOutput("session_status"),
          shiny::tags$details(
            shiny::tags$summary("Connection details"),
            shiny::uiOutput("connection_status")
          ),
          shiny::tags$details(
            shiny::tags$summary("Test connection recovery"),
            shiny::p(
              "Break this session's connection. The next read detects the failure; another reload opens a fresh connection."
            ),
            shiny::div(
              class = "pg-actions",
              button(
                "reset_backend",
                "Break connection",
                "Terminating this session's database connection..."
              ),
              button(
                "retry_native",
                "Try the old connection",
                "Checking that the old connection cannot recover on its own..."
              )
            ),
            shiny::textOutput("recovery_status")
          )
        )
      ),
      # Machine-readable state stays available to browser tests, outside the UI.
      shiny::tags$div(
        hidden = "hidden",
        `aria-hidden` = "true",
        shiny::textOutput("snapshot")
      )
    )
  )
}
