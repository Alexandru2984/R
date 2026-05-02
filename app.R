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
  is_logged_in <- reactiveVal(FALSE)
  
  observeEvent(input$refresh, {
    rv$refresh_trigger <- rv$refresh_trigger + 1
  })
  
  # Hide import tab by default if not logged in
  observe({
    if (!is_logged_in()) {
      nav_hide("main_nav", "Logs & Import")
    } else {
      nav_show("main_nav", "Logs & Import")
    }
  })
  
  # Auth UI - Login / Logout button
  output$auth_button_ui <- renderUI({
    if (is_logged_in()) {
      actionButton("btn_logout", "Logout", class = "btn-outline-danger btn-sm mt-2", icon = icon("sign-out-alt"))
    } else {
      actionButton("btn_login_modal", "Admin Login", class = "btn-outline-info btn-sm mt-2", icon = icon("lock"))
    }
  })
  
  # Demo Banner
  output$demo_banner <- renderUI({
    if (!is_logged_in()) {
      tags$div(class = "alert alert-warning text-center mx-3 mt-3 mb-0", 
               style="border-radius:10px; font-weight:bold; background-color: rgba(239, 68, 68, 0.15); border-color: rgba(239, 68, 68, 0.3); color: #f8fafc;",
               icon("eye-slash"), " PUBLIC DEMO MODE - Showing randomized mock data. Please login to view live production logs."
      )
    }
  })
  
  # Login Modal
  observeEvent(input$btn_login_modal, {
    showModal(modalDialog(
      title = "Admin Authentication",
      textInput("auth_user", "Username"),
      passwordInput("auth_pass", "Password"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_login_submit", "Login", class = "btn-primary")
      )
    ))
  })
  
  # Login submit
  observeEvent(input$btn_login_submit, {
    valid_user <- Sys.getenv("APP_USERNAME", "admin")
    valid_pass <- Sys.getenv("APP_PASSWORD", "change_me")
    
    if (input$auth_user == valid_user && input$auth_pass == valid_pass) {
      is_logged_in(TRUE)
      removeModal()
      showNotification("Logged in successfully. Live production data loaded.", type = "message")
      rv$refresh_trigger <- rv$refresh_trigger + 1
    } else {
      showNotification("Invalid credentials", type = "error")
    }
  })
  
  # Logout
  observeEvent(input$btn_logout, {
    is_logged_in(FALSE)
    showNotification("Logged out. Mock data loaded.", type = "warning")
    rv$refresh_trigger <- rv$refresh_trigger + 1
  })
  
  # Reactive tables depending on auth state
  tbl_req <- reactive({ if(is_logged_in()) "requests" else "mock_requests" })
  tbl_ip <- reactive({ if(is_logged_in()) "ip_summary" else "mock_ip_summary" })
  
  # Helper for dynamic where clauses
  where_data <- reactive({
    rv$refresh_trigger # Depend on refresh button
    
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
        params <- c(params, as.character(date_f[2] + 1))
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
      query_db(pool, paste("SELECT COUNT(*) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$unique_ips <- renderText({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(DISTINCT ip_address) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$sus_bots <- renderText({
    w <- where_data()$req
    bot_cond <- "classification IN ('known_bot', 'scanner', 'suspicious')"
    w$clause <- if (w$clause == "") paste("WHERE", bot_cond) else paste(w$clause, "AND", bot_cond)
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(*) as n FROM", tbl_req(), w$clause), w$params)
    }, error = function(e) data.frame(n=0))
    if(nrow(res)>0) format(as.numeric(res$n[1]), big.mark=",") else "0"
  })
  
  output$sus_404 <- renderText({
    w <- where_data()$req
    cond_404 <- "status_code = 404"
    w$clause <- if (w$clause == "") paste("WHERE", cond_404) else paste(w$clause, "AND", cond_404)
    res <- tryCatch({
      query_db(pool, paste("SELECT COUNT(*) as n FROM", tbl_req(), w$clause), w$params)
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
      query_db(pool, paste("SELECT path, COUNT(*) as count FROM", tbl_req(), w$clause, "GROUP BY path ORDER BY count DESC LIMIT 10"), w$params)
    }, error = function(e) data.frame(path=character(0), count=integer(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_top_ips <- renderDT({
    w <- where_data()$ip
    res <- tryCatch({
      query_db(pool, paste("SELECT ip_address, total_requests, risk_score, classification FROM", tbl_ip(), w$clause, "ORDER BY risk_score DESC LIMIT 10"), w$params)
    }, error = function(e) data.frame(ip=character(0)))
    datatable(res, options = list(pageLength = 5))
  })
  
  output$table_recent_reqs <- renderDT({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT timestamp, ip_address, method, path, status_code, classification FROM", tbl_req(), w$clause, "ORDER BY timestamp DESC LIMIT 50"), w$params)
    }, error = function(e) data.frame())
    datatable(res, options = list(pageLength = 10))
  })
  
  # Plotly Chart
  output$chart_time <- renderPlotly({
    w <- where_data()$req
    res <- tryCatch({
      query_db(pool, paste("SELECT date_trunc('hour', timestamp) as time_bucket, COUNT(*) as count FROM", tbl_req(), w$clause, "GROUP BY time_bucket ORDER BY time_bucket"), w$params)
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