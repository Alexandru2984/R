# R Traffic Intelligence Dashboard

A production-ready R/Shiny web application for analyzing web traffic logs (Nginx/Cloudflare) and distinguishing real human traffic from bots, crawlers, scanners, and suspicious activities.

## Features

- **Nginx & Cloudflare Log Parsers:** Safely parses logs and handles malformed lines.
- **Bot Detection & Scoring:** Uses rule-based scoring combining known bot user-agents, suspicious paths (e.g., `/.env`, `/wp-admin`, SQLi), and behavioral signals (e.g., 404 floods).
- **PostgreSQL Database:** Securely stores imported logs, requests, IP risk summaries, and events.
- **Modern UI:** Built with Shiny, `bslib` (dark cyborg theme), `DT`, and `plotly`.
- **Systemd Integration:** Runs reliably as a background service (`r-traffic-intel.service`).
- **Nginx Reverse Proxy & SSL:** Exposed securely at `https://r.micutu.com`.

## Technology Stack

- **Frontend:** R Shiny, bslib, DT, plotly
- **Backend:** R (dplyr, stringr), PostgreSQL (DBI, RPostgres, pool)
- **Deployment:** Nginx, Systemd, Certbot (Let's Encrypt)

## Directory Structure

```text
/home/micu/r
├── app.R                 # Main Shiny app entry point
├── R/                    # R modules (UI, server, parsers, DB, etc.)
├── scripts/              # Migration, initialization, port selection scripts
├── tests/                # Testthat directory
├── logs/                 # App logs
├── data/                 # Sample data and uploads
├── README.md             # This file
├── .env                  # Environment variables
└── .gitignore
```

## Setup & Deployment

### 1. Database

Initialize PostgreSQL schema:
```bash
sudo -u postgres psql -c "CREATE USER r_traffic_user WITH PASSWORD 'change_me';"
sudo -u postgres psql -c "CREATE DATABASE r_traffic_intel OWNER r_traffic_user;"
PGPASSWORD=change_me psql -U r_traffic_user -d r_traffic_intel -f scripts/init_db.sql
```

### 2. Environment Variables (`.env`)

**Warning: Never commit the `.env` file to version control.** It contains real secrets. Set the variables correctly for the production environment.
A placeholder is generated during initial deployment.

### 3. Run Locally

For local development or testing:
```bash
Rscript -e "shiny::runApp(port=3838)"
```

### 4. Systemd Service

The application is managed by `systemd`. To restart the service:
```bash
sudo systemctl restart r-traffic-intel.service
```
To check logs:
```bash
sudo journalctl -u r-traffic-intel.service -f
```

### 5. Nginx Proxy & SSL

Nginx reverse proxy is configured in `/etc/nginx/sites-available/r.micutu.com`.
The site is secured with Let's Encrypt using Certbot. 

To test configuration and reload Nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Running Tests

To run the full suite of automated tests:
```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

## Troubleshooting

- **App not starting:** Check systemd logs (`journalctl -u r-traffic-intel`). Ensure R packages are fully installed and `.env` is loaded correctly.
- **Port occupied:** The `scripts/choose_port.sh` automatically selects an available port.
- **Nginx 502 Bad Gateway:** The Shiny app might have crashed or isn't running on the specified port. Restart the systemd service.
- **Database Connection Failure:** Verify PostgreSQL is running and `.env` credentials are correct. Check `psql -h 127.0.0.1 -U r_traffic_user -d r_traffic_intel`.
- **Certbot Issues:** Use `sudo certbot renew --dry-run` to test renewals. Ensure port 80 is open and DNS points to the server.
