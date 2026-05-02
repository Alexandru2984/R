# R/summaries.R
library(dplyr)

aggregate_ips <- function(requests_df) {
  if (is.null(requests_df) || nrow(requests_df) == 0) return(NULL)
  
  requests_df %>%
    group_by(ip_address) %>%
    summarize(
      total_requests = n(),
      unique_paths = n_distinct(path),
      error_404_count = sum(status_code == 404, na.rm = TRUE),
      last_seen = max(timestamp, na.rm = TRUE),
      avg_bot_score = mean(bot_score, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      risk_score = avg_bot_score + (error_404_count * 0.5) + (ifelse(total_requests > 1000, 5, 0)),
      classification = case_when(
        risk_score >= 10 ~ "scanner",
        risk_score >= 5 ~ "suspicious",
        TRUE ~ "likely_human"
      )
    )
}
