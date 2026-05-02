# scripts/import_local_nginx.R
# This script automatically imports the local Nginx access logs into the dashboard DB.

source("/home/micu/r/R/config.R")
source("/home/micu/r/R/db.R")
source("/home/micu/r/R/parser_nginx.R")
source("/home/micu/r/R/detection_rules.R")
source("/home/micu/r/R/scoring.R")
source("/home/micu/r/R/summaries.R")

log_files <- c(
  "/var/log/nginx/access.log.1",
  "/var/log/nginx/access.log"
)

pool <- get_db_pool()

for (file_path in log_files) {
  if (file.exists(file_path)) {
    cat(sprintf("Processing %s...\n", file_path))
    
    parsed <- parse_nginx_log(file_path)
    
    if (!is.null(parsed$valid) && nrow(parsed$valid) > 0) {
      scored_data <- score_requests(parsed$valid)
      
      # Insert file record
      res_file <- query_db(pool, "INSERT INTO imported_log_files (filename, file_type) VALUES ($1, $2) RETURNING id", list(basename(file_path), "nginx"))
      file_id <- res_file$id[1]
      
      # Insert requests
      scored_data$file_id <- file_id
      dbAppendTable(pool, "requests", scored_data)
      
      # Update summaries
      ip_sums <- aggregate_ips(scored_data)
      if (!is.null(ip_sums)) {
        for (i in 1:nrow(ip_sums)) {
          row <- ip_sums[i, ]
          q <- "INSERT INTO ip_summary (ip_address, total_requests, unique_paths, error_404_count, risk_score, classification, last_seen) 
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (ip_address) DO UPDATE SET 
                total_requests = ip_summary.total_requests + EXCLUDED.total_requests,
                unique_paths = EXCLUDED.unique_paths,
                error_404_count = ip_summary.error_404_count + EXCLUDED.error_404_count,
                risk_score = GREATEST(ip_summary.risk_score, EXCLUDED.risk_score),
                classification = EXCLUDED.classification,
                last_seen = GREATEST(ip_summary.last_seen, EXCLUDED.last_seen)"
          execute_db(pool, q, list(
            row$ip_address, row$total_requests, row$unique_paths, row$error_404_count, 
            row$risk_score, row$classification, row$last_seen
          ))
        }
      }
      cat(sprintf("Successfully inserted %d requests from %s.\n", nrow(scored_data), file_path))
    } else {
      cat(sprintf("No valid data found in %s.\n", file_path))
    }
  } else {
    cat(sprintf("File %s does not exist.\n", file_path))
  }
}

poolClose(pool)
cat("Finished local import.\n")