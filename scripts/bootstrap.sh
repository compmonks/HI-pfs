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

# Download and run child scripts
SCRIPTS=(cloudflared.sh setup.sh)

for script in "${SCRIPTS[@]}"; do
  echo "⬇️ Downloading $script from GitHub..."
  curl -fsSL "$REPO/$script" -o "/tmp/$script"
  chmod +x "/tmp/$script"

  echo "🚀 Running $script..."
  bash "/tmp/$script"

  echo "🧹 Removing $script..."
  rm -f "/tmp/$script"
done

echo -e "\n✅ HI-pfs bootstrap complete for node '$NODE_NAME'."
