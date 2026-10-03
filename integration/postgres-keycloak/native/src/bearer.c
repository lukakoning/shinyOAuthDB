#define _GNU_SOURCE
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>
#include <libpq-fe.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#ifndef __linux__
#error "pgBearerHook is a Linux-only integration fixture"
#endif
#ifndef LIBPQ_HAS_PROMPT_OAUTH_DEVICE
#error "pgBearerHook requires PostgreSQL 18 libpq headers"
#endif

enum expected_field { ISSUER, SCOPE, HOST, PORT, DBNAME, USER, CLIENT_ID, FIELD_COUNT };

typedef struct {
    SEXP callback;
    SEXP token_sexp;
    const char *expected[FIELD_COUNT];
    char *discovery_oidc;
    char *discovery_oauth;
    char *token;
    size_t token_length;
    PGconn *claimed_connection;
    pthread_t owner_thread;
    PQauthDataHook_type previous;
    int installed;
    int provided;
} bearer_scope;

/* libpq's public hook is process-wide. The fixture allows one synchronous
 * opening on its owning R thread, never an ambient reusable token provider. */
static bearer_scope *active_scope = NULL;

static void erase_token(char *token, size_t length) {
    volatile unsigned char *p = (volatile unsigned char *) token;

    while (length--) *p++ = 0;
}

static int equals(const char *a, const char *b) {
    return a && b && strcmp(a, b) == 0;
}

static const char *option_value(PQconninfoOption *options, const char *key) {
    for (PQconninfoOption *p = options; p && p->keyword; p++) {
        if (strcmp(p->keyword, key) == 0) return p->val;
    }

    return NULL;
}

static int matches_connection(PGconn *conn, bearer_scope *scope) {
    if (!equals(PQhost(conn), scope->expected[HOST]) ||
        !equals(PQport(conn), scope->expected[PORT]) ||
        !equals(PQdb(conn), scope->expected[DBNAME]) ||
        !equals(PQuser(conn), scope->expected[USER])) return 0;

    PQconninfoOption *options = PQconninfo(conn);
    if (!options) return 0;

    int matches =
        equals(option_value(options, "oauth_issuer"), scope->expected[ISSUER]) &&
        equals(option_value(options, "oauth_scope"), scope->expected[SCOPE]) &&
        equals(option_value(options, "oauth_client_id"), scope->expected[CLIENT_ID]) &&
        equals(option_value(options, "require_auth"), "oauth") &&
        equals(option_value(options, "sslmode"), "verify-full") &&
        equals(option_value(options, "gssencmode"), "disable");
    PQconninfoFree(options);

    return matches;
}

static void request_cleanup(PGconn *conn, PGoauthBearerRequest *request) {
    (void) conn;
    /* The scope owns this buffer until the synchronous R callback unwinds.
     * libpq 18 copies it, then invokes cleanup immediately. Do not let libpq
     * free a scope-owned allocation or keep a pointer to it afterwards. */
    request->token = NULL;
    request->user = NULL;
}

static int bearer_hook(PGauthData type, PGconn *conn, void *data) {
    bearer_scope *scope = active_scope;
    if (!scope || !pthread_equal(scope->owner_thread, pthread_self())) return -1;
    if (type == PQAUTHDATA_PROMPT_OAUTH_DEVICE) return -1;
    if (type != PQAUTHDATA_OAUTH_BEARER_TOKEN) {
        return scope->previous ? scope->previous(type, conn, data) : -1;
    }
    if (!conn || !data || !matches_connection(conn, scope)) return -1;
    if (scope->claimed_connection && scope->claimed_connection != conn) return -1;

    PGoauthBearerRequest *request = (PGoauthBearerRequest *) data;
    if (!equals(request->scope, scope->expected[SCOPE]) ||
        !(equals(request->openid_configuration, scope->discovery_oidc) ||
          equals(request->openid_configuration, scope->discovery_oauth))) return -1;

    /* Only the initial connection may consume the token. A later reset inside
     * the RPostgres opening callback also fails, instead of silently retrying. */
    if (scope->provided) return -1;

    scope->claimed_connection = conn;
    scope->provided = 1;
    request->token = scope->token;
    request->cleanup = request_cleanup;
    request->async = NULL;
    request->user = NULL;

    return 1;
}

static char *append(const char *first, const char *second) {
    size_t a = strlen(first), b = strlen(second);
    char *result = malloc(a + b + 1);

    if (result) {
        memcpy(result, first, a);
        memcpy(result + a, second, b + 1);
    }

    return result;
}

static SEXP run_callback(void *data) {
    bearer_scope *scope = data;
    const char *issuer = scope->expected[ISSUER];

    /* OIDC discovery appends its suffix. RFC 8414 discovery inserts the
     * well-known path between the authority and issuer path. */
    scope->discovery_oidc = append(issuer, "/.well-known/openid-configuration");
    const char *path = strchr(issuer + strlen("https://"), '/');
    size_t authority_length = path ? (size_t) (path - issuer) : strlen(issuer);
    const char *suffix = "/.well-known/oauth-authorization-server";
    size_t suffix_length = strlen(suffix), path_length = path ? strlen(path) : 0;
    scope->discovery_oauth = malloc(authority_length + suffix_length + path_length + 1);
    if (scope->discovery_oauth) {
        memcpy(scope->discovery_oauth, issuer, authority_length);
        memcpy(scope->discovery_oauth + authority_length, suffix, suffix_length);
        if (path) memcpy(scope->discovery_oauth + authority_length + suffix_length,
                         path, path_length);
        scope->discovery_oauth[authority_length + suffix_length + path_length] = '\0';
    }

    scope->token_length = strlen(CHAR(STRING_ELT(scope->token_sexp, 0)));
    scope->token = malloc(scope->token_length + 1);
    if (!scope->discovery_oidc || !scope->discovery_oauth || !scope->token)
        Rf_error("Unable to allocate the integration bearer-hook state.");

    memcpy(scope->token, CHAR(STRING_ELT(scope->token_sexp, 0)), scope->token_length + 1);

    scope->owner_thread = pthread_self();
    active_scope = scope;
    PQsetAuthDataHook(bearer_hook);
    scope->installed = 1;

    SEXP call = PROTECT(Rf_lang1(scope->callback));
    SEXP result = Rf_eval(call, R_GlobalEnv);
    UNPROTECT(1);

    return result;
}

static void finish_scope(void *data, Rboolean jump) {
    (void) jump;
    bearer_scope *scope = data;

    if (scope->installed) PQsetAuthDataHook(scope->previous);
    active_scope = NULL;

    if (scope->token) {
        erase_token(scope->token, scope->token_length);
        free(scope->token);
        scope->token = NULL;
    }

    free(scope->discovery_oidc);
    free(scope->discovery_oauth);
}

static void require_libpq18(void) {
    int version = PQlibVersion();
    if (version < 180000 || version >= 190000)
        Rf_error("This integration fixture requires libpq major version 18.");
}

static SEXP checked_string(SEXP value, const char *label) {
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1 ||
        STRING_ELT(value, 0) == NA_STRING || !LENGTH(STRING_ELT(value, 0)))
        Rf_error("%s must be one nonempty string.", label);

    return value;
}

static SEXP C_pg_with_bearer(SEXP token, SEXP expected, SEXP callback) {
    require_libpq18();
    checked_string(token, "token");
    if (TYPEOF(expected) != STRSXP || XLENGTH(expected) != FIELD_COUNT)
        Rf_error("Invalid expected connection metadata.");
    if (!Rf_isFunction(callback)) Rf_error("callback must be a function.");
    if (active_scope) Rf_error("Nested bearer-hook scopes are unsupported.");

    bearer_scope scope;
    memset(&scope, 0, sizeof(scope));
    scope.previous = PQgetAuthDataHook();
    if (scope.previous != PQdefaultAuthDataHook)
        Rf_error("Another libpq OAuth hook is installed; refusing to replace it.");

    for (int i = 0; i < FIELD_COUNT; i++) {
        if (STRING_ELT(expected, i) == NA_STRING || !LENGTH(STRING_ELT(expected, i)))
            Rf_error("Invalid expected connection metadata.");
        scope.expected[i] = CHAR(STRING_ELT(expected, i));
    }
    if (strncmp(scope.expected[ISSUER], "https://", 8) != 0 ||
        strlen(scope.expected[ISSUER]) <= 8)
        Rf_error("The bearer-hook issuer must be an HTTPS issuer identifier.");

    scope.callback = callback;
    scope.token_sexp = token;

    return R_UnwindProtect(run_callback, &scope, finish_scope, &scope, NULL);
}

static SEXP C_pg_bearer_runtime(SEXP dll_path) {
    require_libpq18();
    checked_string(dll_path, "RPostgres DLL path");

    void *handle = dlopen(CHAR(STRING_ELT(dll_path, 0)), RTLD_NOW | RTLD_NOLOAD);
    if (!handle) Rf_error("RPostgres's native library is not already loaded.");

    void *their_hook = dlsym(handle, "PQgetAuthDataHook");
    int same_libpq = their_hook && their_hook == (void *) PQgetAuthDataHook;
    dlclose(handle);
    if (!same_libpq)
        Rf_error("RPostgres and pgBearerHook must resolve the same shared libpq hook.");

    SEXP result = PROTECT(Rf_allocVector(VECSXP, 4));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 4));
    const char *labels[] = {"libpq_version", "same_libpq", "default_hook", "active"};
    for (int i = 0; i < 4; i++) SET_STRING_ELT(names, i, Rf_mkChar(labels[i]));
    SET_VECTOR_ELT(result, 0, Rf_ScalarInteger(PQlibVersion()));
    SET_VECTOR_ELT(result, 1, Rf_ScalarLogical(same_libpq));
    SET_VECTOR_ELT(result, 2, Rf_ScalarLogical(PQgetAuthDataHook() == PQdefaultAuthDataHook));
    SET_VECTOR_ELT(result, 3, Rf_ScalarLogical(active_scope != NULL));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(2);

    return result;
}

/* Internal regression probe. It exposes only a success/denial result, never
 * token bytes. No SQL or OAuth HTTP request is made. */
static SEXP C_pg_bearer_probe(SEXP expected, SEXP discovery, SEXP request_scope,
                             SEXP second_connection) {
    if (!active_scope || TYPEOF(expected) != STRSXP || XLENGTH(expected) != FIELD_COUNT)
        Rf_error("The native probe must run within a bearer-hook test scope.");
    checked_string(discovery, "discovery");
    checked_string(request_scope, "request scope");

    const char *keys[] = {"oauth_issuer", "oauth_scope", "host", "port", "dbname",
                         "user", "oauth_client_id", "sslmode", "require_auth",
                         "gssencmode", "password", "passfile", NULL};
    const char *values[13];
    for (int i = 0; i < FIELD_COUNT; i++) values[i] = CHAR(STRING_ELT(expected, i));
    values[7] = "verify-full";
    values[8] = "oauth";
    values[9] = "disable";
    values[10] = "pgBearerHook-password-disabled";
    values[11] = "/dev/null";
    values[12] = NULL;

    PGconn *conn = PQconnectStartParams(keys, values, 0);
    if (!conn) Rf_error("Unable to allocate the native regression probe.");

    PGoauthBearerRequest request;
    memset(&request, 0, sizeof(request));
    request.openid_configuration = CHAR(STRING_ELT(discovery, 0));
    request.scope = CHAR(STRING_ELT(request_scope, 0));
    int result = PQgetAuthDataHook()(PQAUTHDATA_OAUTH_BEARER_TOKEN, conn, &request);
    if (request.cleanup) request.cleanup(conn, &request);

    if (Rf_asLogical(second_connection)) {
        PGconn *other = PQconnectStartParams(keys, values, 0);
        if (!other) { PQfinish(conn); Rf_error("Unable to allocate second probe connection."); }
        memset(&request, 0, sizeof(request));
        request.openid_configuration = CHAR(STRING_ELT(discovery, 0));
        request.scope = CHAR(STRING_ELT(request_scope, 0));
        int second = PQgetAuthDataHook()(PQAUTHDATA_OAUTH_BEARER_TOKEN, other, &request);
        if (request.cleanup) request.cleanup(other, &request);
        PQfinish(other);
        result = result > 0 && second < 0 ? 1 : 0;
    }

    PQfinish(conn);

    return Rf_ScalarInteger(result);
}

/* R's registered .Call ABI deliberately erases each routine's signature to
 * DL_FUNC. Keep -Wextra elsewhere while silencing only these required casts. */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wcast-function-type"
static const R_CallMethodDef call_methods[] = {
    {"C_pg_with_bearer", (DL_FUNC) &C_pg_with_bearer, 3},
    {"C_pg_bearer_runtime", (DL_FUNC) &C_pg_bearer_runtime, 1},
    {"C_pg_bearer_probe", (DL_FUNC) &C_pg_bearer_probe, 4},
    {NULL, NULL, 0}
};
#pragma GCC diagnostic pop

void attribute_visible R_init_pgBearerHook(DllInfo *dll) {
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
