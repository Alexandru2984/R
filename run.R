port <- suppressWarnings(as.integer(Sys.getenv("APP_PORT", "3838")))
if (is.na(port) || port < 1024L || port > 65535L) stop("APP_PORT must be between 1024 and 65535", call. = FALSE)

shiny::runApp(
  appDir = ".",
  port = port,
  host = "127.0.0.1",
  launch.browser = FALSE
)
