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

# Export for sub-processes
export IPFS_USER EMAIL NODE_NAME TUNNEL_SUBDOMAIN CLOUDFLARE_DOMAIN IS_PRIMARY_NODE

# Set hostname
echo "🔧 Setting hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME"

# Confirm summary
echo -e "\n🧪 Environment Summary:"
echo "  → User:        $IPFS_USER"
echo "  → Hostname:    $NODE_NAME"
echo "  → Domain:      $TUNNEL_SUBDOMAIN.$CLOUDFLARE_DOMAIN"
echo "  → Primary node: $IS_PRIMARY_NODE"

# Download and run/setup scripts
SCRIPTS=(cloudflared.sh setup.sh self-maintenance.sh)

for script in "${SCRIPTS[@]}"; do
  echo "⬇️ Downloading $script from GitHub..."

  if [[ "$script" == "self-maintenance.sh" ]]; then
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

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable self-maintenance.timer
sudo systemctl start self-maintenance.timer

echo -e "\n✅ HI-pfs bootstrap complete for node '$NODE_NAME'."