# R/detection_rules.R

KNOWN_BOT_UAS <- c(
  "Googlebot", "Bingbot", "AhrefsBot", "SemrushBot", "MJ12bot",
  "GPTBot", "ClaudeBot", "Bytespider", "curl", "python-requests",
  "Go-http-client", "masscan", "zgrab", "sqlmap"
)

SUSPICIOUS_PATHS <- c(
  "/.env", "/wp-admin", "/wp-login.php", "/phpmyadmin", "/.git/config",
  "/admin", "/login", "/server-status", "/actuator", "/vendor/phpunit"
)

is_known_bot <- function(ua) {
  if (is.na(ua) || ua == "") return(FALSE)
  pattern <- paste(KNOWN_BOT_UAS, collapse = "|")
  grepl(pattern, ua, ignore.case = TRUE)
}

is_suspicious_path <- function(path) {
  if (is.na(path)) return(FALSE)
  
  # Check exact or start matches
  if (any(sapply(SUSPICIOUS_PATHS, function(p) startsWith(path, p)))) return(TRUE)
  
  # Path traversal
  if (grepl("\\.\\./", path)) return(TRUE)
  
  # SQLi / XSS basic checks
  if (grepl("UNION SELECT", path, ignore.case = TRUE)) return(TRUE)
  if (grepl("<script>", path, ignore.case = TRUE)) return(TRUE)
  
  FALSE
}
