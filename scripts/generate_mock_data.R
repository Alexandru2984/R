# scripts/generate_mock_data.R
source("/home/micu/r/R/config.R")
source("/home/micu/r/R/db.R")
pool <- get_db_pool()
tryCatch({
  execute_db(pool, "DROP TABLE IF EXISTS mock_requests")
  execute_db(pool, "DROP TABLE IF EXISTS mock_ip_summary")
  execute_db(pool, "CREATE TABLE mock_requests (LIKE requests INCLUDING ALL)")
  execute_db(pool, "CREATE TABLE mock_ip_summary (LIKE ip_summary INCLUDING ALL)")
  
  set.seed(123)
  n <- 5000
  timestamps <- Sys.time() - runif(n, 0, 7*24*3600)
  ips <- paste0("10.0.", sample(1:255, n, replace=TRUE), ".", sample(1:255, n, replace=TRUE))
  paths <- sample(c("/", "/home", "/products", "/login", "/.env", "/wp-admin", "/api/v1/data"), n, replace=TRUE, prob=c(30, 20, 20, 10, 5, 5, 10))
  status <- sample(c(200, 301, 403, 404, 500), n, replace=TRUE, prob=c(75, 5, 5, 10, 5))
  classifications <- ifelse(paths %in% c("/.env", "/wp-admin"), "scanner", ifelse(status==404, "suspicious", "likely_human"))
  
  mock_reqs <- data.frame(
    file_id = as.integer(NA),
    ip_address = ips,
    timestamp = timestamps,
    method = "GET",
    path = paths,
    protocol = "HTTP/1.1",
    status_code = status,
    response_size = floor(runif(n, 200, 10000)),
    referrer = "-",
    user_agent = "MockBrowser/1.0",
    bot_score = ifelse(classifications=="scanner", 8.5, 0.0),
    classification = classifications,
    country = as.character(NA),
    stringsAsFactors = FALSE
  )
  
  dbAppendTable(pool, "mock_requests", mock_reqs)
  
  library(dplyr)
  mock_sums <- mock_reqs %>% group_by(ip_address) %>% summarize(
    total_requests = n(),
    unique_paths = n_distinct(path),
    error_404_count = sum(status_code == 404),
    risk_score = max(bot_score) + (error_404_count * 0.5),
    classification = first(classification),
    last_seen = max(timestamp)
  )
  dbAppendTable(pool, "mock_ip_summary", mock_sums)
  cat("Mock data generated successfully.\n")
}, error = function(e) {
  cat("Error:", e$message, "\n")
})
poolClose(pool)