#!/bin/bash
# HI-pfs: Cloudflare Tunnel Setup Script
# This script installs `cloudflared`, creates and configures a tunnel with a public subdomain,
# maps DNS via Cloudflare, and sets up a systemd service to persist the tunnel.

set -euo pipefail

### Function: Print header
print_header() {
  echo "===================================================="
  echo "☁️  HI-pfs: Cloudflare Tunnel Configuration"
  echo "===================================================="
}

### Step 0: Prompt user input
prompt_input() {
  # === Accept Arguments or Fallback to Prompt ===
  TUNNEL_NAME="${1:-}"
  SUBDOMAIN="${2:-}"
  
  if [[ -z "$TUNNEL_NAME" || -z "$SUBDOMAIN" ]]; then
    echo "🔧 Missing arguments. Switching to interactive mode..."
    read -rp "→ Enter unique tunnel name (e.g. ipfs-node-02): " TUNNEL_NAME
    read -rp "→ Enter full subdomain (e.g. ipfs2.example.com): " SUBDOMAIN
  fi

  CONFIG_DIR="/etc/cloudflared"
  CREDENTIAL_FILE="/root/.cloudflared/${TUNNEL_NAME}.json"
  CONFIG_FILE="${CONFIG_DIR}/config.yml"
  SERVICE_NAME="cloudflared"

  echo "📌 Tunnel name: $TUNNEL_NAME"
  echo "🌍 Subdomain:   $SUBDOMAIN"
}

### Step 1: Install cloudflared if missing
install_cloudflared() {
  if ! command -v cloudflared &>/dev/null; then
    echo "🔧 Installing cloudflared..."
    ARCH=$(uname -m)
    case "$ARCH" in
      aarch64) FILE="cloudflared-linux-arm64.deb" ;;
      armv7l)  FILE="cloudflared-linux-arm.deb" ;;
      x86_64)  FILE="cloudflared-linux-amd64.deb" ;;
      *)
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
        ;;
    esac
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/$FILE" -o "/tmp/$FILE"
    sudo dpkg -i "/tmp/$FILE"
  else
    echo "✅ cloudflared already installed."
  fi
}

# == Tunnel Conflict Check ==
EXISTS=$(cloudflared tunnel list --output json | grep -w "\"Name\": \"$TUNNEL_NAME\"" || true)

if [[ -n "$EXISTS" ]]; then
  echo "⚠️ A tunnel named '$TUNNEL_NAME' already exists in Cloudflare."
  select OPTION in "Reuse existing tunnel" "Delete and recreate" "Abort"; do
    case $OPTION in
      "Reuse existing tunnel")
        echo "🔁 Reusing existing tunnel..."
        ;;
      "Delete and recreate")
        echo "🧹 Deleting tunnel remotely..."
        cloudflared tunnel delete "$TUNNEL_NAME" || true
        rm -f "$CREDENTIAL_FILE"
        break
        ;;
      "Abort")
        echo "🚫 Aborting setup."
        exit 1
        ;;
    esac
    break
  done
fi

### Step 2: Authenticate tunnel (opens browser once)
authenticate_cloudflare() {
  echo "🌐 Authenticating tunnel (opens browser)..."
  cloudflared tunnel login
}

### Step 3: Create tunnel (if not already created)
create_tunnel() {
  if [[ ! -f "$CREDENTIAL_FILE" ]]; then
    echo "🚧 Creating tunnel: $TUNNEL_NAME..."
    cloudflared tunnel create "$TUNNEL_NAME"
  else
    echo "✅ Tunnel credentials found at $CREDENTIAL_FILE"
  fi
}

### Step 4: Create cloudflared config.yml
write_config_file() {
  echo "📝 Writing tunnel config to: $CONFIG_FILE"
  sudo mkdir -p "$CONFIG_DIR"
  sudo tee "$CONFIG_FILE" > /dev/null <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $CREDENTIAL_FILE

ingress:
  - hostname: $SUBDOMAIN
    service: http://localhost:8081
  - service: http_status:404
EOF
}

### Step 5: Map the DNS route
map_dns() {
  echo "🔗 Creating DNS route: $SUBDOMAIN → $TUNNEL_NAME"
  cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"
}

### Step 6: Create systemd service to keep tunnel alive
create_systemd_service() {
  echo "🛠️ Creating systemd service for cloudflared"
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

  echo "🔁 Enabling and starting service..."
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME"
}

### Step 7: Completion
print_completion() {
  echo "✅ Tunnel '$TUNNEL_NAME' is now live at:"
  echo "   🌐 https://$SUBDOMAIN"
  echo "🔒 Ensure your DNS is properly configured in your Cloudflare dashboard!"
}

### Main flow
main() {
  print_header
  prompt_input
  install_cloudflared
  authenticate_cloudflare
  create_tunnel
  write_config_file
  map_dns
  create_systemd_service
  print_completion
}

main
