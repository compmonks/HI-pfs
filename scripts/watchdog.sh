#!/bin/bash
# HI-pfs Watchdog: Monitor & auto-recover IPFS, cloudflared, and token-server

USER="${IPFS_USER:-$(whoami)}"
LOGFILE="/home/$USER/ipfs-admin/logs/watchdog.log"
MAILTO="${EMAIL:-compmonks@compmonks.com}"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
STATUS_SUMMARY=""
ALERT_TRIGGERED=0

mkdir -p "$(dirname "$LOGFILE")"

log() {
  echo "[$TIMESTAMP] $1" >> "$LOGFILE"
  STATUS_SUMMARY+="$1\n"
}

check_and_restart() {
  local service=$1
  systemctl is-active --quiet "$service"
  if [[ $? -ne 0 ]]; then
    log "❌ $service is inactive. Attempting restart..."
    systemctl restart "$service"
    sleep 3
    systemctl is-active --quiet "$service"
    if [[ $? -eq 0 ]]; then
      log "✅ $service successfully restarted."
      ALERT_TRIGGERED=1
    else
      log "🚨 $service FAILED to restart!"
      ALERT_TRIGGERED=1
    fi
  else
    log "✅ $service is running."
  fi
}

log "Running watchdog health check on node $(hostname)..."

check_and_restart "ipfs"
check_and_restart "cloudflared"
check_and_restart "token-server"

# Optional: check if IPFS API is reachable
curl -s http://127.0.0.1:5001/api/v0/version >/dev/null || {
  log "⚠️ IPFS API endpoint not responding."
  ALERT_TRIGGERED=1
}

# Email summary if any failure was detected
if [[ "$ALERT_TRIGGERED" -eq 1 && -x "$(command -v mail)" ]]; then
  echo -e "$STATUS_SUMMARY" | mail -s "HI-pfs Watchdog Alert: $(hostname)" "$MAILTO"
fi

log "Watchdog check complete."