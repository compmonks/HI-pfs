#!/bin/bash
# Script to create and configure a new Cloudflare Tunnel and subdomain for a new IPFS node

read -p "Enter unique tunnel name (e.g. ipfs-node-02): " TUNNEL_NAME
read -p "Enter subdomain for this node (e.g. ipfs2.example.com): " SUBDOMAIN

CONFIG_DIR="/etc/cloudflared"
CREDENTIAL_FILE="/root/.cloudflared/${TUNNEL_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

# Step 1: Install cloudflared if missing
if ! command -v cloudflared &> /dev/null; then
  echo "Installing cloudflared..."
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]]; then
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o /tmp/cloudflared.deb
  else
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm.deb -o /tmp/cloudflared.deb
  fi
  sudo dpkg -i /tmp/cloudflared.deb
fi

# Step 2: Authenticate if needed
cloudflared tunnel login

# Step 3: Create the tunnel
cloudflared tunnel create "$TUNNEL_NAME"

# Step 4: Generate config.yml
sudo mkdir -p "$CONFIG_DIR"
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $CREDENTIAL_FILE

ingress:
  - hostname: $SUBDOMAIN
    service: http://localhost:8081
  - service: http_status:404
EOF

# Step 5: Map the subdomain
cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"

# Step 6: Enable and start the tunnel
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared

# Done
echo "✅ Tunnel '$TUNNEL_NAME' is live and mapped to https://$SUBDOMAIN"
echo "🌐 Make sure '$SUBDOMAIN' is added to your Cloudflare DNS zone."
