# R/config.R
# Read .env file manually since dotenv might not be installed

load_env <- function(env_file = ".env") {
  if (file.exists(env_file) && file.access(env_file, 4) == 0) {
    lines <- readLines(env_file, warn = FALSE)
    lines <- lines[trimws(lines) != ""]
    lines <- lines[!grepl("^#", trimws(lines))]
    for (line in lines) {
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        key <- trimws(parts[1])
        value <- trimws(paste(parts[-1], collapse = "="))
        if (is.na(Sys.getenv(key, unset = NA_character_))) {
          args <- list(value)
          names(args) <- key
          do.call(Sys.setenv, args)
        }
      }
    }
  }
}

# Ensure env is loaded
load_env()

required_env <- function(name) {
  value <- Sys.getenv(name, "")
  if (!nzchar(value)) stop(sprintf("Required environment variable %s is missing", name), call. = FALSE)
  value
}

get_config <- function() {
  list(
    db_host = Sys.getenv("DB_HOST", "127.0.0.1"),
    db_port = as.integer(Sys.getenv("DB_PORT", "5432")),
    db_name = required_env("DB_NAME"),
    db_user = required_env("DB_USER"),
    db_password = required_env("DB_PASSWORD"),
    log_dir = Sys.getenv("LOG_DIR", "logs"),
    data_dir = Sys.getenv("DATA_DIR", "data")
  )
}
