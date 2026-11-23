# R/scoring.R

score_requests <- function(df) {
  if (is.null(df)) return(df)
  
  df$bot_score <- rep(0.0, nrow(df))
  df$classification <- rep("unknown", nrow(df))
  if (!nrow(df)) return(df)
  
  # Score user agents
  bot_values <- unique(df$user_agent)
  bot_idx <- vapply(bot_values, is_known_bot, logical(1))[match(df$user_agent, bot_values)]
  df$bot_score[bot_idx] <- df$bot_score[bot_idx] + 5.0
  
  empty_ua_idx <- is.na(df$user_agent) | df$user_agent == "-" | trimws(df$user_agent) == ""
  df$bot_score[empty_ua_idx] <- df$bot_score[empty_ua_idx] + 2.0
  
  # Score paths
  path_values <- unique(df$path)
  suspicious_path_idx <- vapply(path_values, is_suspicious_path, logical(1))[match(df$path, path_values)]
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
