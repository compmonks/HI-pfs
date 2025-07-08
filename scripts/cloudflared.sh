#!/bin/bash
# HI-pfs: Cloudflare Tunnel Setup for IPFS Node
# This script installs cloudflared, creates a named tunnel, maps a subdomain, and installs systemd config

set -e

read -p "Enter unique tunnel name (e.g. ipfs-node-02): " TUNNEL_NAME
read -p "Enter full subdomain (e.g. ipfs2.example.com): " SUBDOMAIN

CONFIG_DIR="/etc/cloudflared"
CREDENTIAL_FILE="/root/.cloudflared/${TUNNEL_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
SERVICE_NAME="cloudflared"

# 1. Install cloudflared if missing
if ! command -v cloudflared &> /dev/null; then
  echo "🔧 Installing cloudflared..."
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]]; then
    FILE="cloudflared-linux-arm64.deb"
  elif [[ "$ARCH" == "armv7l" ]]; then
    FILE="cloudflared-linux-arm.deb"
  else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
  fi

  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/$FILE" -o "/tmp/$FILE"
  sudo dpkg -i "/tmp/$FILE"
fi

# 2. Authenticate tunnel access
echo "🌐 Opening browser for Cloudflare login..."
cloudflared tunnel login

# 3. Create tunnel if not already present
if [[ ! -f "$CREDENTIAL_FILE" ]]; then
  echo "🚧 Creating tunnel $TUNNEL_NAME..."
  cloudflared tunnel create "$TUNNEL_NAME"
else
  echo "✅ Tunnel $TUNNEL_NAME already exists (credentials found)."
fi

# 4. Create config.yml
echo "📝 Writing config to $CONFIG_FILE..."
sudo mkdir -p "$CONFIG_DIR"
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $CREDENTIAL_FILE

ingress:
  - hostname: $SUBDOMAIN
    service: http://localhost:8081
  - service: http_status:404
EOF

# 5. Create DNS route
echo "🔗 Mapping DNS $SUBDOMAIN to tunnel..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"

# 6. Create systemd service (optional if not already installed)
echo "🛠️ Enabling systemd tunnel service..."
sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/cloudflared tunnel --config $CONFIG_FILE run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "✅ Tunnel '$TUNNEL_NAME' is now running at https://$SUBDOMAIN"
echo "🧩 Make sure $SUBDOMAIN exists in your Cloudflare DNS zone."