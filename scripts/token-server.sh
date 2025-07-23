# pylint: skip-file
#!/bin/bash
# ============================================================================
# HI-pfs Token Server Setup
# Configures a Flask token server as a systemd service
# ============================================================================

set -euo pipefail

ENV_FILE="/etc/hi-pfs.env"

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1091
  source "$ENV_FILE"
else
  echo "❌ Missing environment file: $ENV_FILE" >&2
  exit 1
fi

echo "===================================================="
echo "🔑  HI-pfs: Token Server Configuration"
echo "===================================================="

WORKING_DIR="/home/$IPFS_USER/token-server"
REMOTE_ADMIN_DIR="/home/$IPFS_USER/ipfs-admin"

echo "🗄️ Preparing token server files and directories..."
mkdir -p "$WORKING_DIR"
mkdir -p "$REMOTE_ADMIN_DIR"/{zips,tokens,logs}
echo "${IS_PRIMARY_NODE:-n}" | sudo tee "$REMOTE_ADMIN_DIR/role.txt" > /dev/null
ln -sfn "$REMOTE_ADMIN_DIR/zips" "$WORKING_DIR/zips"
ln -sfn "$REMOTE_ADMIN_DIR/tokens" "$WORKING_DIR/tokens"
ln -sfn "$REMOTE_ADMIN_DIR/logs" "$WORKING_DIR/logs"
if [[ ! -f "$WORKING_DIR/server.py" ]]; then
  echo "❌ $WORKING_DIR/server.py not found. Please run setup.sh first." >&2
  exit 1
fi
echo "✓ Token server directories and symlinks ready."

echo "🛠️ Creating systemd service for token-server..."
sudo tee /etc/systemd/system/token-server.service > /dev/null <<EOF
[Unit]
Description=Token ZIP Flask Server
After=network.target ipfs.service
Requires=ipfs.service

[Service]
WorkingDirectory=$WORKING_DIR
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/python3 server.py
User=$IPFS_USER
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "🔁 Enabling and starting token-server service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable token-server
sudo systemctl restart token-server

sleep 2
if systemctl is-active --quiet token-server; then
  echo "✅ Token server service is running on port 8082."
else
  echo "❌ Token server service failed to start. Check logs with: journalctl -u token-server -e"
fi
