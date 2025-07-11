#!/bin/bash
# HI-pfs INIT - Resets a Raspberry Pi to prepare for fresh node setup
# Author: CompMonks / HI-pfs
# Description: Stops services, cleans old config, unmounts SSD, resets environment
# Usage: Run before bootstrap.sh on reused or misconfigured nodes

set -e

### CONFIG
USER_HOME="/home/$(whoami)"
LOG_TAG="[HI-pfs INIT]"
VERBOSE=true

log() {
  [[ "$VERBOSE" == true ]] && echo "$LOG_TAG $1"
}

log "🧹 Starting HI-pfs node cleanup..."

#--------------------------------------#
# 1. STOP & DISABLE ALL SYSTEM SERVICES
#--------------------------------------#
SERVICES=(ipfs caddy cloudflared token-server cid-autosync heartbeat watchdog)

log "→ Stopping and disabling HI-pfs related services..."
for svc in "${SERVICES[@]}"; do
  sudo systemctl stop "$svc" 2>/dev/null || true
  sudo systemctl disable "$svc" 2>/dev/null || true
done

# Remove timers too
TIMERS=(self-maintenance.timer watchdog.timer heartbeat.timer cid-autosync.timer)
for timer in "${TIMERS[@]}"; do
  sudo systemctl stop "$timer" 2>/dev/null || true
  sudo systemctl disable "$timer" 2>/dev/null || true
done

# Clear unit files
log "→ Removing systemd unit files..."
for unit in "${SERVICES[@]}" "${TIMERS[@]}"; do
  sudo rm -f "/etc/systemd/system/$unit.service" "/etc/systemd/system/$unit.timer"
done

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

#--------------------------------------#
# 2. UNMOUNT SSD
#--------------------------------------#
log "→ Attempting to unmount SSD from /mnt/ipfs..."
sudo umount /mnt/ipfs 2>/dev/null || log "  ⚠️ SSD already unmounted."
sudo rm -rf /mnt/ipfs

#--------------------------------------#
# 3. CLEAN USER DATA
#--------------------------------------#
log "→ Removing user and app config directories..."
rm -rf "$USER_HOME/token-server"
rm -rf "$USER_HOME/ipfs-admin"
rm -rf "$USER_HOME/Dropbox/IPFS-Logs"
rm -rf "$USER_HOME/.ipfs" "$USER_HOME/.config/IPFS" "$USER_HOME/.cache/ipfs"
rm -rf "$USER_HOME/.config/autostart/ipfs-desktop.desktop"
rm -f "$USER_HOME/sync-now.sh" "$USER_HOME/swarm.key"
rm -f "$USER_HOME/PEERS.txt" "$USER_HOME/shared-cids.txt"

#--------------------------------------#
# 4. REMOVE SYSTEM FILES (IPFS, CADDY, CLOUDFLARED)
#--------------------------------------#
log "→ Clearing Caddy and Cloudflared configurations..."
sudo rm -rf /etc/caddy/Caddyfile /etc/cloudflared/config.yml
sudo rm -rf /root/.cloudflared
sudo rm -f /etc/hi-pfs.env

# Optional: remove IPFS and cloudflared binaries
if command -v ipfs &> /dev/null; then
  log "→ Removing IPFS binary..."
  sudo rm -f "$(command -v ipfs)"
fi

if command -v cloudflared &> /dev/null; then
  log "→ Removing cloudflared binary..."
  sudo rm -f "$(command -v cloudflared)"
fi

#--------------------------------------#
# 5. DONE
#--------------------------------------#
log "✅ Cleanup complete. Reboot recommended before next install."
