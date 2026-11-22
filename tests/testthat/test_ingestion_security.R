source("../../R/parser_nginx.R")
source("../../R/parser_cloudflare.R")
source("../../R/detection_rules.R")

test_that("IP validation rejects malformed identities and accepts IPv6", {
  expect_equal(valid_ip(c("192.0.2.1", "2001:db8::1", "::1", "::ffff:192.0.2.1", "999.2.3.4", "1:2:3", "1::2::3", "x", NA)),
               c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
})

test_that("uploads cannot read files outside the R temporary directory", {
  outside <- tempfile(tmpdir = "/var/tmp")
  writeLines("data", outside)
  on.exit(unlink(outside))
  expect_error(check_import_file(outside, uploaded = TRUE), "location")
})

test_that("Cloudflare's actual status field and nanosecond timestamps parse", {
  file <- tempfile()
  on.exit(unlink(file))
  writeLines(c("ClientIP,EdgeStartTimestamp,ClientRequestURI,EdgeResponseStatus,ClientRequestUserAgent",
               "192.0.2.1,1795380000000000000,/products,200,Mozilla/5.0",
               "bad-ip,2026-11-22T12:00:00Z,/,200,Mozilla/5.0",
               "192.0.2.2,not-a-date,/,200,Mozilla/5.0"), file)
  parsed <- parse_cloudflare_csv(file)
  expect_equal(nrow(parsed$valid), 1L)
  expect_equal(parsed$valid$status_code, 200L)
  expect_equal(length(parsed$invalid), 2L)
})

test_that("encoded probes are found without accusing normal login routes", {
  expect_false(is_suspicious_path("/login"))
  expect_false(is_suspicious_path("/admin"))
  expect_true(is_suspicious_path("/%252eenv"))
  expect_true(is_suspicious_path("/search?q=UNION%20SELECT%201"))
  expect_true(is_suspicious_path("/static/%2e%2e/etc/passwd"))
})

test_that("nginx semantic errors are rejected", {
  file <- tempfile()
  on.exit(unlink(file))
  writeLines(c('999.0.0.1 - - [22/Nov/2026:12:00:00 +0000] "GET / HTTP/1.1" 200 12 "-" "Mozilla"',
               '192.0.2.1 - - [99/Nov/2026:12:00:00 +0000] "GET / HTTP/1.1" 200 12 "-" "Mozilla"'), file)
  parsed <- parse_nginx_log(file)
  expect_equal(nrow(parsed$valid), 0L)
  expect_equal(length(parsed$invalid), 2L)
})
