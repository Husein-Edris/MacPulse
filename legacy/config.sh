#!/bin/bash
# ============================================================
#  MONITORING CONFIG — Edit your websites & settings here
# ============================================================

# --- Websites to monitor (add as many as you need) ----------
WEBSITES=(
    "https://edrishusein.com/"
    "https://www.virtualinternships.com/"
    "https://bemsventures.de/"
    "https://susanne-barth.com/"
    "https://www.martina-velmeden.de/"
    "https://ideel.ch/"
)

# --- Check interval in seconds (600 = 10 minutes) ----------
CHECK_INTERVAL=600

# --- Timeout per website request (seconds) ------------------
CURL_TIMEOUT=15

# --- Log file location --------------------------------------
LOG_DIR="/Users/edrishusein/Local Sites/monitoring/logs"
LOG_FILE="$LOG_DIR/monitoring.log"
LATEST_FILE="$LOG_DIR/latest.json"

# --- Server monitoring (local machine) ----------------------
# Set to "yes" to collect CPU, RAM, disk, uptime
MONITOR_SERVER="yes"

# Disk paths to check (space-separated)
DISK_PATHS="/"

# --- Alerts (optional) --------------------------------------
# Set to "yes" to get macOS notifications on failures
NOTIFY_ON_FAILURE="yes"

# CPU usage % threshold to trigger alert
CPU_ALERT_THRESHOLD=90

# Disk usage % threshold to trigger alert
DISK_ALERT_THRESHOLD=85

# RAM usage % threshold to trigger alert
RAM_ALERT_THRESHOLD=90

# --- GitHub ------------------------------------------------
GITHUB_USER="Husein-Edris"
