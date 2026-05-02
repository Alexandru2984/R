# R/config.R
# Read .env file manually since dotenv might not be installed

load_env <- function(env_file = ".env") {
  if (file.exists(env_file)) {
    lines <- readLines(env_file, warn = FALSE)
    lines <- lines[trimws(lines) != ""]
    lines <- lines[!grepl("^#", trimws(lines))]
    for (line in lines) {
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        key <- trimws(parts[1])
        value <- trimws(paste(parts[-1], collapse = "="))
        args <- list(value)
        names(args) <- key
        do.call(Sys.setenv, args)
      }
    }
  }
}

# Ensure env is loaded
load_env()

get_config <- function() {
  list(
    db_host = Sys.getenv("DB_HOST", "127.0.0.1"),
    db_port = as.integer(Sys.getenv("DB_PORT", "5432")),
    db_name = Sys.getenv("DB_NAME", "r_traffic_intel"),
    db_user = Sys.getenv("DB_USER", "r_traffic_user"),
    db_password = Sys.getenv("DB_PASSWORD", "change_me"),
    log_dir = Sys.getenv("LOG_DIR", "logs"),
    data_dir = Sys.getenv("DATA_DIR", "data")
  )
}
