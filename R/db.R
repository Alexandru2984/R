# R/db.R
library(DBI)
library(RPostgres)
library(pool)

# Create a connection pool to PostgreSQL
get_db_pool <- function() {
  cfg <- get_config()
  pool::dbPool(
    drv = RPostgres::Postgres(),
    dbname = cfg$db_name,
    host = cfg$db_host,
    port = cfg$db_port,
    user = cfg$db_user,
    password = cfg$db_password
  )
}

# Query wrapper to return data.table or data.frame
query_db <- function(pool, query, params = list()) {
  if (length(params) == 0) {
    dbGetQuery(pool, query)
  } else {
    res <- dbSendQuery(pool, query)
    dbBind(res, params)
    data <- dbFetch(res)
    dbClearResult(res)
    data
  }
}

execute_db <- function(pool, query, params = list()) {
  if (length(params) == 0) {
    dbExecute(pool, query)
  } else {
    res <- dbSendStatement(pool, query)
    dbBind(res, params)
    rows <- dbGetRowsAffected(res)
    dbClearResult(res)
    rows
  }
}
