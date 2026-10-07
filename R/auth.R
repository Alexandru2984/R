# Authentication helpers shared by the Shiny server and unit tests.

AUTH_MAX_FAILURES <- 5L
AUTH_WINDOW_SECONDS <- 300
AUTH_LOCK_SECONDS <- 600

new_auth_limiter <- function() {
  new.env(parent = emptyenv())
}

auth_client_key <- function(request) {
  forwarded <- request$HTTP_X_REAL_IP
  candidate <- if (!is.null(forwarded) && nzchar(forwarded)) forwarded else request$REMOTE_ADDR
  if (is.null(candidate) || !nzchar(candidate)) candidate <- "unknown"
  candidate <- trimws(strsplit(candidate, ",", fixed = TRUE)[[1]][1])

  if (grepl("^[0-9A-Fa-f:.]+$", candidate)) candidate else "unknown"
}

auth_locked <- function(limiter, key, now = Sys.time()) {
  entry <- limiter[[key]]
  !is.null(entry) && entry$locked_until > now
}

record_auth_failure <- function(limiter, key, now = Sys.time()) {
  entry <- limiter[[key]]

  if (is.null(entry) || difftime(now, entry$window_started, units = "secs") > AUTH_WINDOW_SECONDS) {
    entry <- list(count = 0L, window_started = now, locked_until = as.POSIXct(0, origin = "1970-01-01"))
  }

  entry$count <- entry$count + 1L
  if (entry$count >= AUTH_MAX_FAILURES) entry$locked_until <- now + AUTH_LOCK_SECONDS
  limiter[[key]] <- entry

  auth_locked(limiter, key, now)
}

clear_auth_failures <- function(limiter, key) {
  if (exists(key, envir = limiter, inherits = FALSE)) rm(list = key, envir = limiter)
}

verify_admin_credentials <- function(username, password, expected_user, password_hash) {
  if (!is.character(username) || length(username) != 1L ||
      !is.character(password) || length(password) != 1L ||
      !nzchar(expected_user) || !nzchar(password_hash)) return(FALSE)

  password_ok <- tryCatch(
    sodium::password_verify(password_hash, password),
    error = function(e) FALSE
  )

  isTRUE(identical(enc2utf8(username), enc2utf8(expected_user)) && password_ok)
}
