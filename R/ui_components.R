# R/ui_components.R
library(shiny)
library(bslib)
library(DT)
library(plotly)

# Define a completely custom modern theme
cyber_theme <- bs_theme(
  version = 5,
  bg = "#0b1121",
  fg = "#f8fafc",
  primary = "#06b6d4",    # Cyan
  secondary = "#1e293b",
  success = "#10b981",
  info = "#3b82f6",       # Blue
  warning = "#8b5cf6",    # Purple
  danger = "#ef4444",     # Red
  base_font = font_google("Inter"),
  heading_font = font_google("Inter"),
  code_font = font_google("Fira Code")
)

# Add custom glowing CSS rules
cyber_theme <- bs_add_rules(cyber_theme, "
  /* Custom CSS applied */
  body {
    -webkit-font-smoothing: antialiased;
  }
  .navbar {
    background: rgba(15, 23, 42, 0.8) !important;
    backdrop-filter: blur(12px) !important;
    border-bottom: 1px solid rgba(255,255,255,0.05);
  }
  .navbar-brand {
    font-weight: 800;
    background: linear-gradient(90deg, #06b6d4, #8b5cf6);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    letter-spacing: 0.5px;
  }
  .bslib-sidebar-layout > .collapse-toggle,
  .bslib-sidebar-layout > .sidebar {
    background-color: rgba(30, 41, 59, 0.4) !important;
    backdrop-filter: blur(10px);
    border-right: 1px solid rgba(255,255,255,0.05);
  }
  .card {
    background: linear-gradient(145deg, rgba(30, 41, 59, 0.6), rgba(15, 23, 42, 0.8)) !important;
    border: 1px solid rgba(255, 255, 255, 0.05) !important;
    border-radius: 16px !important;
    box-shadow: 0 10px 30px -10px rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(12px);
    transition: transform 0.2s ease, box-shadow 0.2s ease;
  }
  .card:hover {
    box-shadow: 0 10px 40px -10px rgba(6, 182, 212, 0.15);
    transform: translateY(-2px);
  }
  .card-header {
    background: transparent !important;
    border-bottom: 1px solid rgba(255, 255, 255, 0.05) !important;
    color: #94a3b8;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 1px;
    font-size: 0.85rem;
    padding: 1.25rem 1.5rem;
  }
  .bslib-value-box {
    border: 1px solid rgba(255, 255, 255, 0.05) !important;
    border-radius: 16px !important;
    background: linear-gradient(135deg, rgba(30,41,59,0.8), rgba(15,23,42,0.9)) !important;
    position: relative;
    overflow: hidden;
  }
  .bslib-value-box::before {
    content: '';
    position: absolute;
    top: 0; left: 0; width: 100%; height: 3px;
  }
  .bslib-value-box.bg-primary::before { background: #06b6d4; box-shadow: 0 0 15px #06b6d4; }
  .bslib-value-box.bg-info::before { background: #3b82f6; box-shadow: 0 0 15px #3b82f6; }
  .bslib-value-box.bg-warning::before { background: #8b5cf6; box-shadow: 0 0 15px #8b5cf6; }
  .bslib-value-box.bg-danger::before { background: #ef4444; box-shadow: 0 0 15px #ef4444; }
  
  .value-box-value {
    font-weight: 800 !important;
    font-size: 2.5rem !important;
    background: linear-gradient(to bottom right, #ffffff, #94a3b8);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .value-box-title {
    font-weight: 600;
    color: #cbd5e1 !important;
    text-transform: uppercase;
    letter-spacing: 1px;
    font-size: 0.85rem !important;
  }

  .form-control, .form-select {
    background-color: rgba(15, 23, 42, 0.6) !important;
    border: 1px solid #334155 !important;
    color: #f8fafc !important;
    border-radius: 8px !important;
    padding: 0.6rem 1rem;
  }
  .form-control:focus, .form-select:focus {
    border-color: #06b6d4 !important;
    box-shadow: 0 0 0 3px rgba(6, 182, 212, 0.2) !important;
  }
  .btn-primary {
    background: linear-gradient(90deg, #3b82f6, #06b6d4) !important;
    border: none !important;
    border-radius: 8px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    padding: 0.6rem 1.2rem;
    transition: all 0.3s ease;
  }
  .btn-primary:hover {
    box-shadow: 0 0 15px rgba(6, 182, 212, 0.4);
    transform: translateY(-1px);
  }
  .btn-success {
    background: linear-gradient(90deg, #10b981, #059669) !important;
    border: none !important;
    border-radius: 8px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  table.dataTable { border-collapse: collapse !important; color: #f8fafc; }
  table.dataTable thead th { border-bottom: 1px solid #334155 !important; color: #94a3b8; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; padding: 1rem; }
  table.dataTable tbody tr { background-color: transparent !important; }
  table.dataTable tbody td { border-bottom: 1px solid rgba(255, 255, 255, 0.02) !important; padding: 0.8rem 1rem; }
  table.dataTable tbody tr:hover { background-color: rgba(255, 255, 255, 0.03) !important; }
  .dataTables_wrapper .dataTables_paginate .paginate_button { color: #f8fafc !important; border-radius: 6px; }
  .dataTables_wrapper .dataTables_info { color: #94a3b8 !important; }
  .dataTables_wrapper .dataTables_length, .dataTables_wrapper .dataTables_filter { color: #94a3b8 !important; }
  
  /* Upload status */
  #upload_status {
    color: #10b981;
    font-weight: 600;
  }
")

ui <- page_navbar(
  title = "R Traffic Intelligence",
  theme = cyber_theme,
  fillable = TRUE,
  
  nav_panel("Dashboard",
    layout_sidebar(
      sidebar = sidebar(
        title = HTML("<span style='font-weight:700; letter-spacing:1px; color:#f8fafc'>FILTERS</span>"),
        width = 300,
        dateRangeInput("date_filter", "Date Range", end = Sys.Date(), max = Sys.Date()),
        selectInput("class_filter", "Classification", 
                    choices = c("All", "likely_human", "known_bot", "crawler", "scanner", "suspicious", "unknown")),
        br(),
        actionButton("refresh", "Refresh Data", class = "btn-primary w-100", icon = icon("sync"))
      ),
      
      layout_columns(
        col_widths = c(3, 3, 3, 3),
        value_box("Total Requests", textOutput("total_req"), theme = "primary", showcase = icon("server")),
        value_box("Unique IPs", textOutput("unique_ips"), theme = "info", showcase = icon("users")),
        value_box("Suspected Bots", textOutput("sus_bots"), theme = "warning", showcase = icon("robot")),
        value_box("Suspicious 404s", textOutput("sus_404"), theme = "danger", showcase = icon("exclamation-triangle"))
      ),
      
      layout_columns(
        col_widths = 12,
        card(
          card_header(HTML("<i class='fa fa-chart-line me-2'></i> Requests over Time")),
          card_body(class = "p-0", plotlyOutput("chart_time", height = "350px"))
        )
      ),
      
      layout_columns(
        col_widths = c(6, 6),
        card(
          card_header(HTML("<i class='fa fa-route me-2'></i> Top Paths")),
          card_body(DTOutput("table_top_paths"))
        ),
        card(
          card_header(HTML("<i class='fa fa-shield-alt me-2'></i> Top IPs by Risk")),
          card_body(DTOutput("table_top_ips"))
        )
      )
    )
  ),
  
  nav_panel("Logs & Import",
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header(HTML("<i class='fa fa-upload me-2'></i> Upload Logs")),
        card_body(
          fileInput("log_upload", "Select Log File", accept = c(".log", ".txt", ".csv")),
          radioButtons("log_type", "Log Type", choices = c("Nginx" = "nginx", "Cloudflare" = "cloudflare")),
          br(),
          actionButton("btn_process", "Process File", class = "btn-success w-100", icon = icon("cogs")),
          br(),
          tags$div(class = "mt-3 text-center", textOutput("upload_status"))
        )
      ),
      card(
        card_header(HTML("<i class='fa fa-list me-2'></i> Recent Requests")),
        card_body(DTOutput("table_recent_reqs"))
      )
    )
  )
)