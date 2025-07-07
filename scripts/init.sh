#!/bin/bash
# IPFS node cleanup script to reset a Raspberry Pi before running new bootstrap/setup

echo "🧹 Cleaning up previous IPFS and Cloudflare configurations..."

# Stop and disable services
sudo systemctl stop ipfs 2>/dev/null
sudo systemctl disable ipfs 2>/dev/null

sudo systemctl stop caddy 2>/dev/null
sudo systemctl disable caddy 2>/dev/null

sudo systemctl stop cloudflared 2>/dev/null
sudo systemctl disable cloudflared 2>/dev/null

sudo systemctl stop token-server 2>/dev/null
sudo systemctl disable token-server 2>/dev/null

# Remove systemd service files
sudo rm -f /etc/systemd/system/ipfs.service
sudo rm -f /etc/systemd/system/caddy.service
sudo rm -f /etc/systemd/system/cloudflared.service
sudo rm -f /etc/systemd/system/token-server.service
sudo systemctl daemon-reload

# Remove configuration and runtime files
sudo rm -rf /etc/cloudflared
sudo rm -rf /home/*/.cloudflared
sudo rm -rf /home/*/token-server
sudo rm -rf /mnt/ipfs/*
sudo rm -f /home/*/.config/autostart/ipfs-desktop.desktop

# Clean up logs and cron
sudo rm -f /var/log/ipfs-maintenance.log
sudo crontab -l | grep -v 'ipfs-maintenance.sh' | sudo crontab -

# Clear Caddy configs
sudo rm -rf /etc/caddy
sudo rm -rf /var/lib/caddy

# Hostname update option
read -p "Do you want to change the hostname? (y/n): " CHANGE_HOSTNAME
if [[ "$CHANGE_HOSTNAME" == "y" ]]; then
  read -p "Enter new hostname (or type 'default' to reset to 'raspberrypi'): " NEW_HOSTNAME
  if [[ "$NEW_HOSTNAME" == "default" ]]; then
    NEW_HOSTNAME="raspberrypi"
  fi
  sudo hostnamectl set-hostname "$NEW_HOSTNAME"
  sudo sed -i "s/127.0.1.1.*/127.0.1.1       $NEW_HOSTNAME/" /etc/hosts
  echo "✅ Hostname set to $NEW_HOSTNAME"
fi

# Final reboot prompt
read -p "✅ Cleanup complete. Reboot now? (y/n): " REBOOT
if [[ "$REBOOT" == "y" ]]; then
  sudo reboot
else
  echo "⚠️ Reboot recommended before running bootstrap script."
fi
