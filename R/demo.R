# RFC 5737 documentation networks only. Does not connect to production storage.
generate_demo_data <- function(n = 6000L, now = Sys.time(), days = 7L) {
  withr::with_seed(24023, {
    paths <- sample(c("/", "/pricing", "/docs", "/features", "/api/events", "/login", "/.env", "/wp-login.php", "/.git/config", "/search?q=UNION%20SELECT%201"),
      n, replace = TRUE, prob = c(25, 15, 18, 12, 10, 5, 4, 4, 3, 4))
    ua <- sample(c("Mozilla/5.0 (Desktop)", "Mozilla/5.0 (Mobile)", "Googlebot/2.1", "GPTBot/1.0", "python-requests/2.32", "-"),
      n, replace = TRUE, prob = c(40, 32, 10, 7, 7, 4))
    ips <- paste0(sample(c("192.0.2.", "198.51.100.", "203.0.113."), n, replace = TRUE), sample(1:60, n, replace = TRUE))
    # Give scanning IPs repeated bursts so investigations have a meaningful pattern.
    unique_paths <- unique(paths)
    probes <- vapply(unique_paths, is_suspicious_path, logical(1))[match(paths, unique_paths)]
    ips[probes] <- sample(c("192.0.2.201", "198.51.100.202", "203.0.113.203"), sum(probes), replace = TRUE)
    data <- data.frame(timestamp = as.POSIXct(now, tz = "UTC") - runif(n, 0, days * 86400 - 1),
      ip_address = ips, method = sample(c("GET", "POST", "HEAD"), n, TRUE, c(.88, .1, .02)), path = paths,
      protocol = "HTTP/2", status_code = sample(c(200L, 201L, 301L, 403L, 404L, 429L, 500L), n, TRUE, c(78, 2, 7, 4, 6, 2, 1)),
      response_size = sample(150:28000, n, TRUE), referrer = "https://example.com/",
      user_agent = ua, country = sample(c("RO", "DE", "US", "GB", "NL", "FR"), n, TRUE), stringsAsFactors = FALSE)
    data$status_code[probes] <- sample(c(403L, 404L), sum(probes), TRUE)
    data <- score_requests(data)
    data[order(data$timestamp, decreasing = TRUE), , drop = FALSE]
  })
}
