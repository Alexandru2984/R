# app.R
library(shiny)
library(bslib)
library(DT)
library(plotly)
library(dplyr)

# Source modules
source("R/config.R")
source("R/db.R")
source("R/ui_components.R")

# Initialize pool
pool <- NULL

server <- function(input, output, session) {
  
  # Connect to DB
  pool <<- get_db_pool()
  onStop(function() {
    if (!is.null(pool)) poolClose(pool)
  })
  
  # Reactive values
  rv <- reactiveValues(refresh_trigger = 0)
  
  observeEvent(input$refresh, {
    rv$refresh_trigger <- rv$refresh_trigger + 1
  })
  
  # Helper for dynamic where clauses
  where_data <- reactive({
    rv$refresh_trigger # Depend on refresh button, although it will also auto-update on input change
    
    date_f <- input$date_filter
    class_f <- input$class_filter
    
    build_w <- function(prefix = "", is_ip_table = FALSE) {
      where_parts <- c()
      params <- list()
      time_col <- if (is_ip_table) "last_seen" else "timestamp"
      
      if (isTruthy(date_f[1])) {
        param_idx <- length(params) + 1
        where_parts <- c(where_parts, sprintf("%s%s >= $%d", prefix, time_col, param_idx))
        params <- c(params, as.character(date_f[1]))
      }
      if (isTruthy(date_f[2])) {
        param_idx <- length(params) + 1
        where_parts <- c(where_parts, sprintf("%s%s < $%d", prefix, time_col, param_idx))
        params <- c(params, as.character(date_f[2] + 1)) # Next day for inclusive end date
      }
      if (isTruthy(class_f) && class_f != "All") {
        param_idx <- length(params) + 1
        where_parts <- c(where_parts, sprintf("%sclassification = $%d", prefix, param_idx))
        params <- c(params, class_f)
      }
      
      clause <- if (length(where_parts) > 0) paste("WHERE", paste(where_parts, collapse = " AND ")) else ""
      list(clause = clause, params = params)
    }
    
    list(
      req = build_w(is_ip_table = FALSE),
      ip = build_w(is_ip_table = TRUE)
    )
  })
  
  # Value Boxes
  output$total_req <- renderText({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(*) as n FROM requests", w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$unique_ips <- renderText({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(DISTINCT ip_address) as n FROM requests", w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$sus_bots <- renderText({
    w <- where_data()$req
    bot_cond <- "classification IN ('known_bot', 'scanner', 'suspicious')"
    w$clause <- if (w$clause == "") paste("WHERE", bot_cond) else paste(w$clause, "AND", bot_cond)
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(*) as n FROM requests", w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$sus_404 <- renderText({
    w <- where_data()$req
    cond_404 <- "status_code = 404"
    w$clause <- if (w$clause == "") paste("WHERE", cond_404) else paste(w$clause, "AND", cond_404)
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(*) as n FROM requests", w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  # Handle upload
  observeEvent(input$btn_process, {
    req(input$log_upload)
    output$upload_status <- renderText("Processing...")
    
    file_path <- input$log_upload$datapath
    file_type <- input$log_type
    
    tryCatch({
      source("R/parser_nginx.R")
      source("R/parser_cloudflare.R")
      source("R/scoring.R")
      source("R/summaries.R")
      
      if (file_type == "nginx") {
        parsed <- parse_nginx_log(file_path)
      } else {
        parsed <- parse_cloudflare_csv(file_path)
      }
      
      if (!is.null(parsed$valid) && nrow(parsed$valid) > 0) {
        scored_data <- score_requests(parsed$valid)
        res_file <- query_db(pool, "INSERT INTO imported_log_files (filename, file_type) VALUES ($1, $2) RETURNING id", list(input$log_upload$name, file_type))
        file_id <- res_file$id[1]
        
        scored_data$file_id <- file_id
        dbAppendTable(pool, "requests", scored_data)
        
        ip_sums <- aggregate_ips(scored_data)
        if (!is.null(ip_sums)) {
          for (i in 1:nrow(ip_sums)) {
            row <- ip_sums[i, ]
            q <- "INSERT INTO ip_summary (ip_address, total_requests, unique_paths, error_404_count, risk_score, classification, last_seen) 
                  VALUES ($1, $2, $3, $4, $5, $6, $7)
                  ON CONFLICT (ip_address) DO UPDATE SET 
                  total_requests = ip_summary.total_requests + EXCLUDED.total_requests,
                  unique_paths = EXCLUDED.unique_paths,
                  error_404_count = ip_summary.error_404_count + EXCLUDED.error_404_count,
                  risk_score = GREATEST(ip_summary.risk_score, EXCLUDED.risk_score),
                  classification = EXCLUDED.classification,
                  last_seen = GREATEST(ip_summary.last_seen, EXCLUDED.last_seen)"
            execute_db(pool, q, list(
              row$ip_address, row$total_requests, row$unique_paths, row$error_404_count, 
              row$risk_score, row$classification, row$last_seen
            ))
          }
        }
        
        output$upload_status <- renderText(sprintf("Success! Inserted %d requests.", nrow(scored_data)))
        rv$refresh_trigger <- rv$refresh_trigger + 1
      } else {
        output$upload_status <- renderText("No valid data found in file.")
      }
    }, error = function(e) {
      output$upload_status <- renderText(paste("Error processing file:", e$message))
    })
  })
  
  # DT outputs
  output$table_top_paths <- renderDT({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT path, COUNT(*) as count FROM requests", w$clause, "GROUP BY path ORDER BY count DESC LIMIT 10"), w$params)
    }, error = function(e) data.frame(path=character(0), count=integer(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_top_ips <- renderDT({
    w <- where_data()$ip
    res <- tryCatch({
      query_db(pool, paste("SELECT ip_address, total_requests, risk_score, classification FROM ip_summary", w$clause, "ORDER BY risk_score DESC LIMIT 10"), w$params)
    }, error = function(e) data.frame(ip=character(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_recent_reqs <- renderDT({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT timestamp, ip_address, method, path, status_code, classification FROM requests", w$clause, "ORDER BY timestamp DESC LIMIT 50"), w$params)
    }, error = function(e) data.frame())
    datatable(res, options = list(pageLength = 10))
  })
  
  # Plotly Chart
  output$chart_time <- renderPlotly({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT date_trunc('hour', timestamp) as time_bucket, COUNT(*) as count FROM requests", w$clause, "GROUP BY time_bucket ORDER BY time_bucket"), w$params)
    }, error = function(e) data.frame(time_bucket=Sys.time(), count=0))
    
    if (nrow(res) > 0) {
      plot_ly(res, x = ~time_bucket, y = ~count, type = 'scatter', mode = 'lines+markers',
              line = list(color = '#06b6d4', width = 3),
              marker = list(color = '#8b5cf6', size = 8)) %>%
        layout(
          title = "",
          xaxis = list(title = "", gridcolor = 'rgba(255,255,255,0.05)', color = '#94a3b8'), 
          yaxis = list(title = "Requests", gridcolor = 'rgba(255,255,255,0.05)', color = '#94a3b8'),
          plot_bgcolor = 'transparent',
          paper_bgcolor = 'transparent',
          margin = list(l=40, r=20, t=20, b=40)
        )
    } else {
      plot_ly() %>% layout(
        title = list(text = "No data", font = list(color = '#94a3b8')),
        plot_bgcolor = 'transparent',
        paper_bgcolor = 'transparent'
      )
    }
  })
}

shinyApp(ui, server)
