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

log "🚀 HI-pfs Bootstrap Initializing..."

#-------------#
# 1. PROMPT ENV VARS
#-------------#
read -p "Enter your Pi admin username (default: compmonks): " IPFS_USER
IPFS_USER="${IPFS_USER:-compmonks}"

read -p "Enter your email for node alerts and sync reports: " EMAIL
read -p "Enter a hostname for this node (e.g. ipfs-node-00): " NODE_NAME
read -p "Enter your desired Cloudflare Tunnel subdomain (e.g. ipfs0): " TUNNEL_NAME
read -p "Enter your Cloudflare domain (e.g. example.com): " CLOUDFLARE_DOMAIN
read -p "Is this the first (primary) node in the network? (y/n): " IS_PRIMARY_NODE
read -p "Enter minimum SSD size in GB (default: 1000): " MIN_SIZE_GB
MIN_SIZE_GB="${MIN_SIZE_GB:-1000}"

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
export IPFS_USER EMAIL NODE_NAME TUNNEL_NAME CLOUDFLARE_DOMAIN IS_PRIMARY_NODE MIN_SIZE_GB

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
# 6. RUN CLOUDLFARED & SETUP.SH
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
