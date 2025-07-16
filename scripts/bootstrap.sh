# pylint: skip-file
#!/bin/bash
# HI-pfs Bootstrap Script — Interactive Master Installer
# Author: CompMonks / HI-pfs
# Description: Sets environment, downloads core scripts, registers timers and services

set -euo pipefail

#-------------#
# CONFIG
#-------------#
REPO="https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts"
ENVFILE="/etc/hi-pfs.env"
USER_HOME="/home/$(whoami)"
SCRIPTS_DIR="$USER_HOME/scripts"
LOG_TAG="[BOOTSTRAP]"
VERBOSE=true

log() {
  [[ "$VERBOSE" == true ]] && echo "$LOG_TAG $1"
}

#--------------------------------------#
# OPTIONAL CLEANUP (INIT.SH LOGIC)
#--------------------------------------#
cleanup_node() {
  local USER_HOME="/home/$(whoami)"
  local SERVICES=(ipfs caddy cloudflared token-server cid-autosync heartbeat watchdog)
  local TIMERS=(self-maintenance.timer watchdog.timer heartbeat.timer cid-autosync.timer)

  log "🧹 Starting HI-pfs node cleanup..."

  log "→ Stopping and disabling HI-pfs related services..."
  for svc in "${SERVICES[@]}"; do
    sudo systemctl stop "$svc" 2>/dev/null || true
    sudo systemctl disable "$svc" 2>/dev/null || true
  done

  for timer in "${TIMERS[@]}"; do
    sudo systemctl stop "$timer" 2>/dev/null || true
    sudo systemctl disable "$timer" 2>/dev/null || true
  done

  log "→ Removing systemd unit files..."
  for unit in "${SERVICES[@]}" "${TIMERS[@]}"; do
    sudo rm -f "/etc/systemd/system/$unit.service" "/etc/systemd/system/$unit.timer"
  done

  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload

  log "→ Attempting to unmount SSD from /mnt/ipfs..."
  sudo umount /mnt/ipfs 2>/dev/null || log "  ⚠️ SSD already unmounted."
  sudo rm -rf /mnt/ipfs

  log "→ Removing user and app config directories..."
  rm -rf "$USER_HOME/token-server"
  rm -rf "$USER_HOME/ipfs-admin"
  rm -rf "$USER_HOME/Dropbox/IPFS-Logs"
  rm -rf "$USER_HOME/.ipfs" "$USER_HOME/.config/IPFS" "$USER_HOME/.cache/ipfs"
  rm -rf "$USER_HOME/.config/autostart/ipfs-desktop.desktop"
  rm -f "$USER_HOME/sync-now.sh" "$USER_HOME/swarm.key"
  rm -f "$USER_HOME/PEERS.txt" "$USER_HOME/shared-cids.txt"

  log "→ Clearing Caddy and Cloudflared configurations..."
  sudo rm -rf /etc/caddy/Caddyfile /etc/cloudflared/config.yml
  sudo rm -rf /etc/cloudflared /root/.cloudflared ~/.cloudflared /usr/local/bin/cloudflared /usr/bin/cloudflared
  sudo rm -f /etc/hi-pfs.env

  if command -v ipfs &> /dev/null; then
    log "→ Removing IPFS binary..."
    sudo rm -f "$(command -v ipfs)"
  fi

  if command -v cloudflared &> /dev/null; then
    log "→ Removing cloudflared binary..."
    sudo rm -f "$(command -v cloudflared)"
  fi

  log "✅ Cleanup complete. Reboot recommended before next install."
}

log "🚀 HI-pfs Bootstrap Initializing..."

read -p "Run cleanup before bootstrap? (y/N): " RUN_CLEANUP
if [[ "$RUN_CLEANUP" =~ ^[Yy]$ ]]; then
  cleanup_node
fi

#-------------#
# 1. PROMPT ENV VARS
#-------------#
read -p "Enter your Pi admin username (default: compmonks): " IPFS_USER
IPFS_USER="${IPFS_USER:-compmonks}"

while true; do
  read -p "Enter your email for node alerts and sync reports: " EMAIL
  if [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    break
  else
    echo "Invalid email address. Please try again."
  fi
done
read -p "Enter your Cloudflare domain (e.g. example.com): " CLOUDFLARE_DOMAIN
read -p "Is this the first (primary) node in the network? (y/n): " IS_PRIMARY_NODE
read -p "Enter minimum SSD size in GB (default: 1000): " MIN_SIZE_GB
MIN_SIZE_GB="${MIN_SIZE_GB:-1000}"

# Generate node hostname and tunnel name automatically
generate_names() {
  if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
    NODE_NAME="ipfs-node-00"
    TUNNEL_SUBDOMAIN="ipfs0"
  else
    read -p "Enter hostname or IP of the last node: " LAST_NODE
    log "🔗 Fetching info from $LAST_NODE..."
    LAST_ENV=$(ssh "${IPFS_USER}@${LAST_NODE}" "cat /etc/hi-pfs.env" 2>/dev/null || true)
    if [[ -z "$LAST_ENV" ]]; then
      echo "❌ Unable to retrieve environment from $LAST_NODE"
      exit 1
    fi
    LAST_NODE_NAME=$(echo "$LAST_ENV" | grep '^NODE_NAME=' | cut -d= -f2)
    IDX=$(echo "$LAST_NODE_NAME" | grep -o '[0-9]*$')
    IDX=${IDX#0}
    IDX=${IDX:-0}
    NEXT_IDX=$((IDX + 1))
    NODE_NAME=$(printf 'ipfs-node-%02d' "$NEXT_IDX")
    TUNNEL_SUBDOMAIN=$(printf 'ipfs%d' "$NEXT_IDX")
  fi
}

generate_names

#-------------#
# 2. EXPORT ENVIRONMENT
#-------------#
log "📦 Saving environment variables to $ENVFILE..."
sudo tee "$ENVFILE" > /dev/null <<EOF
IPFS_USER=$IPFS_USER
EMAIL=$EMAIL
NODE_NAME=$NODE_NAME
TUNNEL_SUBDOMAIN=$TUNNEL_SUBDOMAIN
CLOUDFLARE_DOMAIN=$CLOUDFLARE_DOMAIN
IS_PRIMARY_NODE=$IS_PRIMARY_NODE
MIN_SIZE_GB=$MIN_SIZE_GB
EOF

# Make available in current shell
export IPFS_USER EMAIL NODE_NAME TUNNEL_SUBDOMAIN CLOUDFLARE_DOMAIN IS_PRIMARY_NODE MIN_SIZE_GB

#-------------#
# 3. HOSTNAME SETUP
#-------------#
log "🔧 Setting hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME" || log "⚠️ Could not change hostname (may require reboot)."

#-------------#
# 4. DISPLAY SUMMARY
#-------------#
echo -e "\n🧪 Environment Summary:"
echo "  → User:         $IPFS_USER"
echo "  → Hostname:     $NODE_NAME"
echo "  → Domain:       $TUNNEL_SUBDOMAIN.$CLOUDFLARE_DOMAIN"
echo "  → Primary Node: $IS_PRIMARY_NODE"
echo "  → SSD Min Size: ${MIN_SIZE_GB}GB"

#-------------#
# 5. SCRIPT DOWNLOADS
#-------------#
SCRIPTS=(
  cloudflared.sh
  setup.sh
  self-maintenance.sh
  watchdog.sh
  diagnostics.sh
  heartbeat.sh
  role-check.sh
  promote.sh
  demote.sh
)

mkdir -p "$SCRIPTS_DIR"
for script in "${SCRIPTS[@]}"; do
  log "⬇️ Downloading $script..."
  curl -fsSL "$REPO/$script" -o "$SCRIPTS_DIR/$script"
  chmod +x "$SCRIPTS_DIR/$script"
  chown "$IPFS_USER:$IPFS_USER" "$SCRIPTS_DIR/$script"
  log "✅ $script saved to $SCRIPTS_DIR/"
done

#-------------#
# 6. RUN CLOUDFLARED & SETUP.SH
#-------------#
log "⚙️ Running cloudflared.sh setup..."
bash "$SCRIPTS_DIR/cloudflared.sh"

log "🧠 Starting main setup.sh for IPFS and services..."
bash "$SCRIPTS_DIR/setup.sh"

#-------------#
# 7. CREATE SYSTEMD TIMERS
#-------------#

## Self-maintenance timer
log "🔁 Registering self-maintenance systemd timer..."
sudo tee /etc/systemd/system/self-maintenance.service > /dev/null <<EOF
[Unit]
Description=HI-pfs Self-Maintenance Script
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENVFILE
ExecStart=$SCRIPTS_DIR/self-maintenance.sh
User=$IPFS_USER
EOF

sudo tee /etc/systemd/system/self-maintenance.timer > /dev/null <<EOF
[Unit]
Description=Runs HI-pfs Self-Maintenance Daily

[Timer]
OnCalendar=03:30
Persistent=true

[Install]
WantedBy=timers.target
EOF

## Watchdog timer
log "🔁 Registering watchdog systemd timer..."
sudo tee /etc/systemd/system/watchdog.service > /dev/null <<EOF
[Unit]
Description=HI-pfs Watchdog Health Check
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENVFILE
ExecStart=$SCRIPTS_DIR/watchdog.sh
User=$IPFS_USER
EOF

sudo tee /etc/systemd/system/watchdog.timer > /dev/null <<EOF
[Unit]
Description=Runs HI-pfs Watchdog every 15 min

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

## Heartbeat (only for primary)
if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
  log "❤️ Registering heartbeat timer for primary node..."
  sudo tee /etc/systemd/system/heartbeat.service > /dev/null <<EOF
[Unit]
Description=HI-pfs Heartbeat Broadcaster
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENVFILE
ExecStart=$SCRIPTS_DIR/heartbeat.sh
User=$IPFS_USER
EOF

  sudo tee /etc/systemd/system/heartbeat.timer > /dev/null <<EOF
[Unit]
Description=HI-pfs heartbeat every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

#-------------#
# 8. START TIMERS
#-------------#
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable self-maintenance.timer watchdog.timer
sudo systemctl start self-maintenance.timer watchdog.timer

if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
  sudo systemctl enable heartbeat.timer
  sudo systemctl start heartbeat.timer
fi

#-------------#
# 9. DONE
#-------------#
echo
log "💡 To check your node status, add this to ~/.bashrc:"
echo "alias hi-pfs='bash $SCRIPTS_DIR/diagnostics.sh'"
echo "Then run: source ~/.bashrc"
echo
log "✅ HI-pfs bootstrap complete for node '$NODE_NAME'"
