# Authentication helpers shared by the Shiny server and unit tests.

AUTH_MAX_FAILURES <- 5L
AUTH_WINDOW_SECONDS <- 300
AUTH_LOCK_SECONDS <- 600
AUTH_MAX_KEYS <- 2048L
AUTH_IDLE_SECONDS <- 1800
AUTH_SESSION_SECONDS <- 28800

scalar_text <- function(x, max_bytes = 1024L) {
  is.character(x) && length(x) == 1L && !is.na(x) &&
    nchar(x, type = "bytes") <= max_bytes
}

new_auth_limiter <- function() {
  new.env(parent = emptyenv())
}

auth_client_key <- function(request) {
  remote <- request$REMOTE_ADDR
  forwarded <- request$HTTP_X_REAL_IP
  trusted <- scalar_text(remote, 45L) && remote %in% c("127.0.0.1", "::1", "::ffff:127.0.0.1")
  candidate <- if (trusted && scalar_text(forwarded, 45L) && nzchar(forwarded)) forwarded else remote
  if (!scalar_text(candidate, 45L) || !nzchar(candidate)) return("unknown")

  if (grepl("^[0-9A-Fa-f:.]+$", candidate)) candidate else "unknown"
}

auth_locked <- function(limiter, key, now = Sys.time()) {
  entry <- limiter[[key]]
  if (is.null(entry) && length(ls(limiter, all.names = TRUE)) >= AUTH_MAX_KEYS) entry <- limiter[["overflow"]]
  !is.null(entry) && entry$locked_until > now
}

record_auth_failure <- function(limiter, key, now = Sys.time(), max_failures = AUTH_MAX_FAILURES) {
  keys <- ls(limiter, all.names = TRUE)
  if (length(keys) >= AUTH_MAX_KEYS) {
    stale <- vapply(keys, function(k) {
      x <- limiter[[k]]
      x$locked_until <= now && difftime(now, x$window_started, units = "secs") > AUTH_WINDOW_SECONDS
    }, logical(1))
    if (any(stale)) rm(list = keys[stale], envir = limiter)
    # Collapse excess identities into a shared bucket instead of allocating forever.
    if (length(ls(limiter, all.names = TRUE)) >= AUTH_MAX_KEYS && !exists(key, limiter, inherits = FALSE)) key <- "overflow"
  }
  entry <- limiter[[key]]

  if (is.null(entry) || difftime(now, entry$window_started, units = "secs") > AUTH_WINDOW_SECONDS) {
    entry <- list(count = 0L, window_started = now, locked_until = as.POSIXct(0, origin = "1970-01-01"))
  }

  entry$count <- entry$count + 1L
  if (entry$count >= max_failures) entry$locked_until <- now + AUTH_LOCK_SECONDS
  limiter[[key]] <- entry

  auth_locked(limiter, key, now)
}

clear_auth_failures <- function(limiter, key) {
  if (exists(key, envir = limiter, inherits = FALSE)) rm(list = key, envir = limiter)
}

verify_admin_credentials <- function(username, password, expected_user, password_hash) {
  if (!scalar_text(username, 128L) || !scalar_text(password) ||
      !scalar_text(expected_user, 128L) || !scalar_text(password_hash) ||
      !nzchar(expected_user) || !nzchar(password_hash)) return(FALSE)

  password_ok <- tryCatch(
    sodium::password_verify(password_hash, password),
    error = function(e) FALSE
  )

  isTRUE(identical(enc2utf8(username), enc2utf8(expected_user)) && password_ok)
}

admin_session_valid <- function(started, active, now = Sys.time()) {
  !is.null(started) && !is.null(active) &&
    isTRUE(as.numeric(difftime(now, started, units = "secs")) < AUTH_SESSION_SECONDS) &&
    isTRUE(as.numeric(difftime(now, active, units = "secs")) < AUTH_IDLE_SECONDS)
}
