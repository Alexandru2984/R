# Start a loopback-only browser test server against an explicitly named test DB.
name <- Sys.getenv("TEST_DB_NAME", "")
if (!grepl("^rtraffic_(test|qa)[_a-z0-9]*$", name)) stop("TEST_DB_NAME must name a dedicated rtraffic_test or rtraffic_qa database.")
Sys.setenv(DB_NAME = name, DB_HOST = Sys.getenv("TEST_DB_HOST", ""),
  DB_USER = Sys.getenv("TEST_DB_USER", Sys.info()[["user"]]),
  DB_PASSWORD = Sys.getenv("TEST_DB_PASSWORD", "unused-local-qa"),
  APP_USERNAME = "qa", APP_PASSWORD_HASH = sodium::password_store("local-qa-only"),
  APP_PORT = Sys.getenv("QA_PORT", "43838"))
source("R/config.R")
source("R/db.R")
setup <- function() {
  db_pool <- get_db_pool()
  on.exit(pool::poolClose(db_pool), add = TRUE)
  con <- pool::poolCheckout(db_pool)
  on.exit(pool::poolReturn(con), add = TRUE, after = FALSE)
  for (file in c("scripts/init_db.sql", sort(list.files("scripts/migrations", pattern = "[.]sql$", full.names = TRUE)))) {
    DBI::dbExecute(con, paste(readLines(file), collapse = "\n"), immediate = TRUE)
  }
}
setup()
source("run.R")
