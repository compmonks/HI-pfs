#!/bin/bash
# HI-pfs INIT - Reset a Raspberry Pi for a clean HI-pfs node setup
# This script removes all services, configs, and mount points previously used by the HI-pfs infrastructure.

set -e

echo -e "\n🧹 [HI-pfs INIT] Starting cleanup and reset process...\n"

### SERVICES TO RESET
SERVICES=(
  ipfs
  caddy
  cloudflared
  token-server
)

echo "→ Stopping and disabling systemd services..."
for svc in "${SERVICES[@]}"; do
  echo "  • Stopping service: $svc"
  sudo systemctl stop "$svc" 2>/dev/null || true
  echo "  • Disabling service: $svc"
  sudo systemctl disable "$svc" 2>/dev/null || true
done

echo "→ Removing service files from /etc/systemd/system/..."
for svc in "${SERVICES[@]}"; do
  SERVICE_FILE="/etc/systemd/system/${svc}.service"
  if [[ -f "$SERVICE_FILE" ]]; then
    echo "  • Removing $SERVICE_FILE"
    sudo rm -f "$SERVICE_FILE"
  fi
done

echo "→ Reloading systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

### UNMOUNT AND DELETE STORAGE
echo -e "\n→ Checking for /mnt/ipfs..."
if mountpoint -q /mnt/ipfs; then
  echo "  • Unmounting /mnt/ipfs..."
  sudo umount /mnt/ipfs
fi

echo "  • Removing /mnt/ipfs directory..."
sudo rm -rf /mnt/ipfs

### REMOVE USER CONFIGS
echo -e "\n→ Removing user-specific configs and data..."
rm -rf ~/token-server ~/Dropbox/IPFS-Logs ~/ipfs-admin
rm -rf ~/.ipfs ~/.config/IPFS ~/.cache/ipfs
rm -rf ~/.config/autostart/ipfs-desktop.desktop
rm -f ~/sync-now.sh ~/swarm.key ~/PEERS.txt ~/shared-cids.txt

### REMOVE CADDY AND CLOUDFLARE CONFIGS
echo -e "\n→ Cleaning up Caddy and Cloudflare configuration files..."
sudo rm -rf /etc/caddy/Caddyfile /etc/cloudflared/config.yml /root/.cloudflared

### REMOVE IPFS BINARY
if command -v ipfs &> /dev/null; then
  echo "→ Removing IPFS binary..."
  sudo rm -f "$(command -v ipfs)"
fi

### REMOVE CLOUDFLARED BINARY
if command -v cloudflared &> /dev/null; then
  echo "→ Removing cloudflared binary..."
  sudo rm -f "$(command -v cloudflared)"
fi

echo -e "\n✅ [HI-pfs INIT] Cleanup complete."
echo "🔁 Reboot recommended or run ./bootstrap.sh to begin a new setup."
