KNOWN_BOT_UAS <- c("Googlebot", "Bingbot", "AhrefsBot", "SemrushBot", "MJ12bot",
  "GPTBot", "ClaudeBot", "Bytespider", "curl", "python-requests", "Go-http-client",
  "masscan", "zgrab", "sqlmap", "PetalBot", "Applebot", "facebookexternalhit")

is_known_bot <- function(ua) {
  if (length(ua) != 1L || is.na(ua) || !nzchar(ua)) return(FALSE)
  grepl(paste(KNOWN_BOT_UAS, collapse = "|"), ua, ignore.case = TRUE)
}

decode_probe <- function(path) {
  value <- substr(path, 1, 8192L)
  for (i in 1:2) value <- tryCatch(utils::URLdecode(value), error = function(e) value)
  tolower(gsub("+", " ", value, fixed = TRUE))
}

is_suspicious_path <- function(path) {
  if (length(path) != 1L || is.na(path)) return(FALSE)
  value <- decode_probe(path)
  # Normal login/admin routes alone are not evidence of a scanner.
  sensitive <- "^/([.]env([./?]|$)|[.]git(/|$)|wp-admin(/|[?]|$)|wp-login[.]php|phpmyadmin(/|[?]|$)|server-status(/|[?]|$)|actuator(/|[?]|$)|vendor/phpunit(/|$))"
  grepl(sensitive, value) || grepl("../", value, fixed = TRUE) ||
    grepl("..\\", value, fixed = TRUE) || grepl("union[[:space:]]+(all[[:space:]]+)?select", value) ||
    grepl("<script([[:space:]>])", value) || grepl("/etc/passwd", value, fixed = TRUE)
}

request_reason <- function(path, ua) {
  if (is_suspicious_path(path)) return("Sensitive path or injection probe (+8)")
  if (is_known_bot(ua)) return("Bot/tool user agent claim (+5); identity unverified")
  if (is.na(ua) || !nzchar(trimws(ua)) || ua == "-") return("Missing user agent (+2); insufficient evidence")
  "No configured rule matched; humanity unverified"
}
