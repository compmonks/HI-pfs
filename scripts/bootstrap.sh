#!/bin/bash
# HI-pfs Bootstrap Script — Master launcher with remote GitHub-sourced scripts

set -e

# GitHub base (customize to your repo)
REPO="https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts"

# Prompt user for environment
read -p "Enter your Pi admin username (default: compmonks): " IPFS_USER
IPFS_USER="${IPFS_USER:-compmonks}"

read -p "Enter your email for node alerts and sync reports: " EMAIL
read -p "Enter a hostname for this node (e.g. ipfs-node-00): " NODE_NAME
read -p "Enter your desired Cloudflare Tunnel subdomain (e.g. ipfs0): " TUNNEL_SUBDOMAIN
read -p "Enter your Cloudflare domain (e.g. example.com): " CLOUDFLARE_DOMAIN
read -p "Is this the first (primary) node in the network? (y/n): " IS_PRIMARY_NODE
read -p "Enter minimum SSD size in GB (default: 1000): " MIN_SIZE_GB
MIN_SIZE_GB="${MIN_SIZE_GB:-1000}"

# Export for sub-processes
export IPFS_USER EMAIL NODE_NAME TUNNEL_SUBDOMAIN CLOUDFLARE_DOMAIN IS_PRIMARY_NODE MIN_SIZE_GB

# Save to environment file for sourcing by services
ENVFILE="/etc/hi-pfs.env"
echo "Saving persistent environment to $ENVFILE"

sudo tee "$ENVFILE" > /dev/null <<EOF
IPFS_USER=$IPFS_USER
EMAIL=$EMAIL
NODE_NAME=$NODE_NAME
TUNNEL_SUBDOMAIN=$TUNNEL_SUBDOMAIN
CLOUDFLARE_DOMAIN=$CLOUDFLARE_DOMAIN
IS_PRIMARY_NODE=$IS_PRIMARY_NODE
MIN_SIZE_GB=$MIN_SIZE_GB
EOF

# Set hostname
echo "🔧 Setting hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME"

# ✅ Fix hostname resolution in /etc/hosts
if ! grep -q "$NODE_NAME" /etc/hosts; then
  echo "🛠 Adding $NODE_NAME to /etc/hosts..."
  echo "127.0.1.1 $NODE_NAME" | sudo tee -a /etc/hosts > /dev/null
  echo "✓ Hostname resolution fixed in /etc/hosts."
fi

# Confirm summary
echo -e "\n🧪 Environment Summary:"
echo "  → User:        $IPFS_USER"
echo "  → Hostname:    $NODE_NAME"
echo "  → Domain:      $TUNNEL_SUBDOMAIN.$CLOUDFLARE_DOMAIN"
echo "  → Primary node: $IS_PRIMARY_NODE"
echo "  → SSD Min Size: ${MIN_SIZE_GB}GB"

# Download and run/setup scripts
SCRIPTS=(cloudflared.sh setup.sh self-maintenance.sh watchdog.sh diagnostics.sh heartbeat.sh role-check.sh promote.sh demote.sh)

for script in "${SCRIPTS[@]}"; do
  echo "⬇️ Downloading $script from GitHub..."

  if [[ "$script" =~ \.(sh|py)$ ]]; then
    mkdir -p "/home/$IPFS_USER/scripts"
    curl -fsSL "$REPO/$script" -o "/home/$IPFS_USER/scripts/$script"
    chmod +x "/home/$IPFS_USER/scripts/$script"
    chown $IPFS_USER:$IPFS_USER "/home/$IPFS_USER/scripts/$script"
    echo "✓ Saved $script to /home/$IPFS_USER/scripts/"
  else
    curl -fsSL "$REPO/$script" -o "/tmp/$script"
    chmod +x "/tmp/$script"
    bash "/tmp/$script"
    rm -f "/tmp/$script"
  fi

echo "✅ $script processed."
done

# Setup systemd timer for self-maintenance
echo "🔁 Configuring self-maintenance systemd timer..."
TIMER_PATH="/etc/systemd/system/self-maintenance.timer"
SERVICE_PATH="/etc/systemd/system/self-maintenance.service"

sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=HI-pfs Self-Maintenance Service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENVFILE
ExecStart=/home/$IPFS_USER/scripts/self-maintenance.sh
User=$IPFS_USER
EOF

sudo tee "$TIMER_PATH" > /dev/null <<EOF
[Unit]
Description=Runs HI-pfs Self-Maintenance Daily

[Timer]
OnCalendar=03:30
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Setup watchdog timer
echo "🔁 Configuring watchdog systemd timer..."
WD_TIMER="/etc/systemd/system/watchdog.timer"
WD_SERVICE="/etc/systemd/system/watchdog.service"

sudo tee "$WD_SERVICE" > /dev/null <<EOF
[Unit]
Description=HI-pfs Watchdog Service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENVFILE
ExecStart=/home/$IPFS_USER/scripts/watchdog.sh
User=$IPFS_USER
EOF

sudo tee "$WD_TIMER" > /dev/null <<EOF
[Unit]
Description=Run watchdog every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Add role transition timers
if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
  echo "🔁 Setting up heartbeat timer for PRIMARY node..."
  sudo tee /etc/systemd/system/heartbeat.timer > /dev/null <<EOF
[Unit]
Description=Primary Node Heartbeat

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

  sudo tee /etc/systemd/system/heartbeat.service > /dev/null <<EOF
[Unit]
Description=HI-pfs Heartbeat Writer

[Service]
Type=oneshot
ExecStart=/home/$IPFS_USER/scripts/heartbeat.sh
User=$IPFS_USER
EOF

  sudo systemctl enable heartbeat.timer
  sudo systemctl start heartbeat.timer
else
  echo "🔁 Setting up role-check timer for SECONDARY node..."
  sudo tee /etc/systemd/system/role-check.timer > /dev/null <<EOF
[Unit]
Description=Check if node should become primary

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target
EOF

  sudo tee /etc/systemd/system/role-check.service > /dev/null <<EOF
[Unit]
Description=HI-pfs Role Check Script

[Service]
Type=oneshot
ExecStart=/home/$IPFS_USER/scripts/role-check.sh
User=$IPFS_USER
EOF

  sudo systemctl enable role-check.timer
  sudo systemctl start role-check.timer
fi

# Finalize timers
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable self-maintenance.timer watchdog.timer
sudo systemctl start self-maintenance.timer watchdog.timer

# Optional CLI alias suggestion
echo "\n💡 To quickly check your node status, add this line to ~/.bashrc:"
echo "alias hi-pfs='bash /home/$IPFS_USER/scripts/diagnostics.sh'"
echo "Then run: source ~/.bashrc"

echo -e "\n✅ HI-pfs bootstrap complete for node '$NODE_NAME'."
