source("../../R/auth.R")

test_that("credential verification uses the configured password hash", {
  password_hash <- sodium::password_store("correct horse battery staple")

  expect_true(verify_admin_credentials("admin", "correct horse battery staple", "admin", password_hash))
  expect_false(verify_admin_credentials("other", "correct horse battery staple", "admin", password_hash))
  expect_false(verify_admin_credentials("admin", "wrong", "admin", password_hash))
  expect_false(verify_admin_credentials("admin", "correct horse battery staple", "", password_hash))
  expect_false(verify_admin_credentials("admin", "correct horse battery staple", "admin", ""))
})

test_that("failed attempts lock and successful authentication can clear state", {
  limiter <- new_auth_limiter()
  key <- "192.0.2.1"
  now <- as.POSIXct("2026-10-07 12:00:00", tz = "UTC")

  for (attempt in seq_len(AUTH_MAX_FAILURES - 1L)) {
    expect_false(record_auth_failure(limiter, key, now + attempt))
  }

  expect_true(record_auth_failure(limiter, key, now + AUTH_MAX_FAILURES))
  expect_true(auth_locked(limiter, key, now + AUTH_MAX_FAILURES + 1L))

  clear_auth_failures(limiter, key)
  expect_false(auth_locked(limiter, key, now + AUTH_MAX_FAILURES + 1L))
})

test_that("failure windows expire before counting new attempts", {
  limiter <- new_auth_limiter()
  key <- "198.51.100.2"
  now <- as.POSIXct("2026-10-07 12:00:00", tz = "UTC")

  expect_false(record_auth_failure(limiter, key, now))
  expect_false(record_auth_failure(limiter, key, now + AUTH_WINDOW_SECONDS + 1))
  expect_equal(limiter[[key]]$count, 1L)
})

test_that("malformed credentials fail closed and proxy trust is bounded", {
  expect_false(verify_admin_credentials(NA_character_, NA_character_, "admin", "hash"))
  expect_false(verify_admin_credentials(rep("admin", 2), "x", "admin", "hash"))
  expect_false(verify_admin_credentials("admin", paste(rep("x", 1025), collapse = ""), "admin", "hash"))
  expect_equal(auth_client_key(list(REMOTE_ADDR = "192.0.2.1", HTTP_X_REAL_IP = "198.51.100.1")), "192.0.2.1")
  expect_equal(auth_client_key(list(REMOTE_ADDR = "127.0.0.1", HTTP_X_REAL_IP = "198.51.100.1")), "198.51.100.1")
})

test_that("admin sessions have both idle and absolute expiration", {
  now <- Sys.time()
  expect_true(admin_session_valid(now, now, now + 30))
  expect_false(admin_session_valid(now, now, now + AUTH_IDLE_SECONDS))
  expect_false(admin_session_valid(now - AUTH_SESSION_SECONDS, now, now))
})
