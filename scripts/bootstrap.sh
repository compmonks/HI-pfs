#!/bin/bash
# HI-pfs bootstrap script to download and execute the full IPFS node setup

SETUP_URL="https://raw.githubusercontent.com/TheComputationalMonkeys/HI-pfs/main/scripts/setup.sh"
TUNNEL_SCRIPT_URL="https://raw.githubusercontent.com/TheComputationalMonkeys/HI-pfs/main/scripts/cloudflared.sh"
SETUP_TEMP="/tmp/ipfs-setup.sh"
TUNNEL_TEMP="/tmp/cloudflared.sh"

# Download and run cloudflared tunnel creation script
echo "🔽 Downloading Cloudflare tunnel script from $TUNNEL_SCRIPT_URL..."
curl -fsSL "$TUNNEL_SCRIPT_URL" -o "$TUNNEL_TEMP"

if [ $? -ne 0 ]; then
  echo "❌ Failed to download tunnel script. Exiting."
  exit 1
fi

chmod +x "$TUNNEL_TEMP"
echo "🚀 Executing tunnel script..."
"$TUNNEL_TEMP"

# Download and run setup.sh
echo "🔽 Downloading setup script from $SETUP_URL..."
curl -fsSL "$SETUP_URL" -o "$SETUP_TEMP"

if [ $? -ne 0 ]; then
  echo "❌ Failed to download setup script. Exiting."
  exit 1
fi

chmod +x "$SETUP_TEMP"
echo "🚀 Executing setup script..."
"$SETUP_TEMP"

# Clean up temporary files
echo "🧹 Cleaning up..."
rm -f "$SETUP_TEMP" "$TUNNEL_TEMP"
echo "✅ All setup scripts executed and removed."
