# R/scoring.R

score_requests <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  
  df$bot_score <- 0.0
  df$classification <- "unknown"
  
  # Score user agents
  bot_idx <- sapply(df$user_agent, is_known_bot)
  df$bot_score[bot_idx] <- df$bot_score[bot_idx] + 5.0
  
  empty_ua_idx <- is.na(df$user_agent) | df$user_agent == "-" | trimws(df$user_agent) == ""
  df$bot_score[empty_ua_idx] <- df$bot_score[empty_ua_idx] + 2.0
  
  # Score paths
  suspicious_path_idx <- sapply(df$path, is_suspicious_path)
  df$bot_score[suspicious_path_idx] <- df$bot_score[suspicious_path_idx] + 8.0
  
  # Set classifications
  df$classification[bot_idx] <- "known_bot"
  df$classification[suspicious_path_idx] <- "scanner"
  
  # If still unknown but has score > 0
  susp_idx <- df$classification == "unknown" & df$bot_score >= 5.0
  df$classification[susp_idx] <- "suspicious"
  
  human_idx <- df$classification == "unknown" & df$bot_score < 2.0
  df$classification[human_idx] <- "likely_human"
  
  df
}
