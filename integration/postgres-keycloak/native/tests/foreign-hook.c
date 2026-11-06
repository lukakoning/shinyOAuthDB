#include <R.h>
#include <Rinternals.h>
#include <libpq-fe.h>

static PQauthDataHook_type previous;
static int installed;

static int foreign_hook(PGauthData type, PGconn *connection, void *data) {
    (void) type;
    (void) connection;
    (void) data;
    return -1;
}

SEXP fixture_foreign_hook(SEXP enable) {
    if (Rf_asLogical(enable)) {
        if (installed) Rf_error("Fixture hook already installed.");
        previous = PQgetAuthDataHook();
        PQsetAuthDataHook(foreign_hook);
        installed = 1;
    } else if (installed) {
        PQsetAuthDataHook(previous);
        installed = 0;
    }
    return Rf_ScalarLogical(PQgetAuthDataHook() == foreign_hook);
}

SEXP fixture_foreign_current(void) {
    return Rf_ScalarLogical(PQgetAuthDataHook() == foreign_hook);
}
