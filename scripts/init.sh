#!/bin/bash
# HI-pfs INIT - Resets a Raspberry Pi to prepare for fresh node setup

echo "🧹 HI-pfs Node Cleanup Starting..."

SERVICES=(
  ipfs
  caddy
  cloudflared
  token-server
)

# Stop and disable relevant services
echo "→ Stopping services..."
for svc in "${SERVICES[@]}"; do
  sudo systemctl stop "$svc" 2>/dev/null
  sudo systemctl disable "$svc" 2>/dev/null
done

# Remove service files
echo "→ Removing systemd service files..."
for svc in "${SERVICES[@]}"; do
  sudo rm -f "/etc/systemd/system/${svc}.service"
done
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

# Unmount and clear SSD if mounted at /mnt/ipfs
echo "→ Unmounting /mnt/ipfs if mounted..."
sudo umount /mnt/ipfs 2>/dev/null
sudo rm -rf /mnt/ipfs

# Clear user-specific config/data
echo "→ Removing user configs (if exist)..."
rm -rf ~/token-server ~/Dropbox/IPFS-Logs ~/ipfs-admin
rm -rf ~/.ipfs ~/.config/IPFS ~/.cache/ipfs
rm -rf ~/.config/autostart/ipfs-desktop.desktop
rm -f ~/sync-now.sh
rm -f ~/swarm.key
rm -f ~/PEERS.txt ~/shared-cids.txt

# Clean up Caddy and Cloudflare
sudo rm -rf /etc/caddy/Caddyfile /etc/cloudflared/config.yml
sudo rm -rf /root/.cloudflared

# Remove IPFS binary (optional)
echo "→ Checking for IPFS binary..."
if command -v ipfs &> /dev/null; then
  sudo rm -f "$(command -v ipfs)"
fi

# Optional: remove cloudflared
if command -v cloudflared &> /dev/null; then
  sudo rm -f "$(command -v cloudflared)"
fi

echo "✅ Cleanup complete. Reboot now or run ./bootstrap.sh to begin fresh setup."
