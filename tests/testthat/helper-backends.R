capture_backend <- function(authorization, connect, ..., target = NULL,
                            scopes = character(), cache_key = NULL, min_valid_for = 60, session = NULL) {
  list(authorization = authorization, connect = connect, args = list(...),
    target = target, scopes = scopes)
}
