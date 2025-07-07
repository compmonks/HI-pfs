#!/bin/bash
# HI-pfs bootstrap script to download and execute the full IPFS node setup

REPO_URL="https://raw.githubusercontent.com/TheComputationalMonkeys/HI-pfs/main/scripts/setup.sh"
TEMP_SCRIPT="/tmp/ipfs-setup.sh"

echo "🔽 Downloading setup script from $REPO_URL..."
curl -fsSL "$REPO_URL" -o "$TEMP_SCRIPT"

if [ $? -ne 0 ]; then
  echo "❌ Failed to download setup script. Exiting."
  exit 1
fi

chmod +x "$TEMP_SCRIPT"
echo "🚀 Executing setup script..."
"$TEMP_SCRIPT"

echo "🧹 Cleaning up..."
rm -f "$TEMP_SCRIPT"
echo "✅ Setup complete and cleaned up."
