# pylint: skip-file
#!/bin/bash
# ============================================================================
# HI-pfs Cloudflare Tunnel Setup
# Installs cloudflared, creates the tunnel and config, maps DNS and
# registers a systemd service.
# ============================================================================

set -euo pipefail

ENV_FILE="/etc/hi-pfs.env"

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  else
    echo "❌ Missing environment file: $ENV_FILE"
    exit 1
  fi
}

print_header() {
  echo "===================================================="
  echo "☁️  HI-pfs: Cloudflare Tunnel Configuration"
  echo "===================================================="
}

read_params() {
  TUNNEL_NAME="${NODE_NAME:-}"
  SUBDOMAIN="${TUNNEL_SUBDOMAIN:-}.${CLOUDFLARE_DOMAIN:-}"

  if [[ -z "$TUNNEL_NAME" || -z "$SUBDOMAIN" ]]; then
    echo "🔧 Missing environment values. Switching to interactive mode..."
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

install_cloudflared() {
  if command -v cloudflared >/dev/null; then
    echo "✅ cloudflared already installed."
    return
  fi

  echo "🔧 Installing cloudflared..."
  case "$(uname -m)" in
    aarch64) FILE="cloudflared-linux-arm64.deb" ;;
    armv7l)  FILE="cloudflared-linux-arm.deb" ;;
    x86_64)  FILE="cloudflared-linux-amd64.deb" ;;
    *)
      echo "❌ Unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/$FILE" -o "/tmp/$FILE"
  sudo dpkg -i "/tmp/$FILE"
}

handle_existing_tunnel() {
  local exists
  exists=$(cloudflared tunnel list --output json | grep -w "\"Name\": \"$TUNNEL_NAME\"" || true)
  if [[ -z "$exists" ]]; then
    return
  fi

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
}

authenticate_cloudflare() {
  echo "🌐 Authenticating tunnel (opens browser)..."
  cloudflared tunnel login
}

create_tunnel() {
  if [[ -f "$CREDENTIAL_FILE" ]]; then
    echo "✅ Tunnel credentials found at $CREDENTIAL_FILE"
  else
    echo "🚧 Creating tunnel: $TUNNEL_NAME..."
    cloudflared tunnel create "$TUNNEL_NAME"
  fi
}

write_config_file() {
  echo "📝 Writing tunnel config to: $CONFIG_FILE"
  sudo mkdir -p "$CONFIG_DIR"
  sudo tee "$CONFIG_FILE" >/dev/null <<EOF2
tunnel: $TUNNEL_NAME
credentials-file: $CREDENTIAL_FILE

ingress:
  - hostname: $SUBDOMAIN
    service: http://localhost:8081
  - service: http_status:404
EOF2
}

map_dns() {
  echo "🔗 Creating DNS route: $SUBDOMAIN → $TUNNEL_NAME"
  cloudflared tunnel route dns "$TUNNEL_NAME" "$SUBDOMAIN"
}

create_systemd_service() {
  echo "🛠️ Creating systemd service for cloudflared"
  sudo tee /etc/systemd/system/cloudflared.service >/dev/null <<EOF2
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
EOF2

  echo "🔁 Enabling and starting service..."
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME"
}

print_completion() {
  echo "✅ Tunnel '$TUNNEL_NAME' is now live at:"
  echo "   🌐 https://$SUBDOMAIN"
  echo "🔒 Ensure your DNS is properly configured in your Cloudflare dashboard!"
}

main() {
  load_env
  print_header
  read_params
  install_cloudflared
  handle_existing_tunnel
  authenticate_cloudflare
  create_tunnel
  write_config_file
  map_dns
  create_systemd_service
  print_completion
}

main "$@"
