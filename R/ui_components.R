# R/ui_components.R
library(shiny)
library(bslib)
library(DT)
library(plotly)

ui <- page_navbar(
  title = "R Traffic Intelligence",
  theme = bs_theme(version = 5, bootswatch = "cyborg"),
  
  nav_panel("Dashboard",
    layout_sidebar(
      sidebar = sidebar(
        title = "Filters",
        dateRangeInput("date_filter", "Date Range"),
        selectInput("class_filter", "Classification", 
                    choices = c("All", "likely_human", "known_bot", "crawler", "scanner", "suspicious", "unknown")),
        actionButton("refresh", "Refresh Data", class = "btn-primary")
      ),
      
      layout_columns(
        value_box("Total Requests", textOutput("total_req"), theme = "primary"),
        value_box("Unique IPs", textOutput("unique_ips"), theme = "info"),
        value_box("Suspected Bots", textOutput("sus_bots"), theme = "warning"),
        value_box("Suspicious 404s", textOutput("sus_404"), theme = "danger")
      ),
      
      card(
        card_header("Requests over Time"),
        plotlyOutput("chart_time")
      ),
      
      layout_columns(
        card(
          card_header("Top Paths"),
          DTOutput("table_top_paths")
        ),
        card(
          card_header("Top IPs by Risk"),
          DTOutput("table_top_ips")
        )
      )
    )
  ),
  
  nav_panel("Logs & Import",
    card(
      card_header("Upload Logs"),
      fileInput("log_upload", "Upload Nginx or Cloudflare Log", 
                accept = c(".log", ".txt", ".csv")),
      radioButtons("log_type", "Log Type", choices = c("Nginx" = "nginx", "Cloudflare" = "cloudflare")),
      actionButton("btn_process", "Process File", class = "btn-success"),
      textOutput("upload_status")
    ),
    card(
      card_header("Recent Requests"),
      DTOutput("table_recent_reqs")
    )
  )
)
