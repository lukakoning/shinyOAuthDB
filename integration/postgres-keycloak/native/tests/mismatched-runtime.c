#include <stddef.h>

/* A separate lookup address tests runtime rejection without loading a second
 * libpq into the R process or changing the real RPostgres installation. */
void *PQgetAuthDataHook(void) {
    return NULL;
}
