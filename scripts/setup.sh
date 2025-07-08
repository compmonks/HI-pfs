#!/bin/bash
# IPFS Raspberry Pi Node Setup with Secure Remote Admin, Token-Gated ZIP Delivery, Dropbox Log Sync, and Replication Readiness

MOUNT_POINT="/mnt/ipfs"
MIN_SIZE_GB=1000
IPFS_PATH="$MOUNT_POINT/ipfs-data"
REMOTE_ADMIN_DIR="/home/$IPFS_USER/ipfs-admin"
SETUP_VERSION="v1.0.0"
BOOTSTRAP_PEERS_PATH="$(pwd)/PEERS.txt"

# User prompted variables
read -p "Enter your Pi admin/user name: " IPFS_USER
read -p "Enter your email for reports: " EMAIL
read -p "Enter your desired node name (similar logic than hostname eg. ipfs-node-00): " NODE_NAME
read -p "Enter your desired Cloudflare Tunnel subdomain (e.g., ipfs0): " TUNNEL_SUBDOMAIN
read -p "Enter your Cloudflare domain (e.g., example.com): " CLOUDFLARE_DOMAIN
read -p "Enable password protection for IPFS Web UI? (y/n): " ENABLE_AUTH
read -p "Is this the first (primary) node in the network? (y/n): " IS_PRIMARY_NODE

 if [[ "$ENABLE_AUTH" == "y" ]]; then
    read -s -p "Enter password for $IPFS_USER: " ADMIN_PASS
    echo ""
    HASHED_PASS=$(caddy hash-password --plaintext "$ADMIN_PASS")
    AUTH_BLOCK="
  basicauth {
    $ADMIN_USER $HASHED_PASS
  }"
  else
    AUTH_BLOCK=""
  fi

# 0. Prerequisites
prerequisites(){
  echo "[0/6] Installing prerequisites: IPFS, Caddy..."

  # --- Secure Swarm Key Setup ---
echo "🔐 Checking for private swarm.key..."
SWARM_KEY_LOCAL_PATH="$(pwd)/swarm.key"

if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
  if [[ ! -f "$SWARM_KEY_LOCAL_PATH" ]]; then
    echo "  → No swarm.key found. Generating new private swarm key..."
    SWARM_KEY_CONTENT=$(openssl rand -hex 32)
    echo -e "/key/swarm/psk/1.0.0/\n/base16/\n$SWARM_KEY_CONTENT" > "$SWARM_KEY_LOCAL_PATH"
    echo "  ✓ swarm.key generated and saved locally:"
    echo "    → $SWARM_KEY_LOCAL_PATH"
    echo "    ⚠️  Copy this key to all other nodes before running their setup script."
  else
    echo "  ✓ Reusing existing swarm.key:"
    echo "    → $SWARM_KEY_LOCAL_PATH"
  fi
else
  if [[ ! -f "$SWARM_KEY_LOCAL_PATH" ]]; then
    echo "  ❌ swarm.key is required for secondary nodes but not found."
    echo "    → Please place the swarm.key from the primary node into this folder:"
    echo "      → $SWARM_KEY_LOCAL_PATH"
    exit 1
  fi
fi

if [[ "$IS_PRIMARY_NODE" == "n" && -f "$BOOTSTRAP_PEERS_PATH" ]]; then
  echo "🔗 Bootstrap peers found at:"
  echo "   → $BOOTSTRAP_PEERS_PATH"
  
elif [[ "$IS_PRIMARY_NODE" == "n" ]]; then
  echo "  ⚠️  No PEERS.txt found."
  echo "    →  → Please place the PEERS.txt file from the last previously created node here: $BOOTSTRAP_PEERS_PATH"
  exit 1
fi

  
  sudo apt update
  sudo apt install -y curl unzip

  # Install IPFS if not found
  if ! command -v ipfs &>/dev/null; then
    curl -s https://dist.ipfs.tech/go-ipfs/install.sh | sudo bash
  fi

  # Install Caddy if not found
  if ! command -v caddy &>/dev/null; then
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install -y caddy
  fi

  # Ensure Chromium is installed
  if ! command -v chromium-browser &>/dev/null; then
    echo "  → Installing Chromium browser..."
    sudo apt update
    sudo apt install -y chromium-browser
  fi

  # Ensure IPFS Desktop is installed (if using optional desktop app)
  if ! command -v ipfs-desktop &>/dev/null; then
    echo "  → Installing IPFS Desktop..."
    wget -O /tmp/ipfs-desktop.deb https://github.com/ipfs/ipfs-desktop/releases/latest/download/ipfs-desktop-latest-linux.deb
    sudo apt install -y /tmp/ipfs-desktop.deb || echo "  ⚠️ IPFS Desktop install failed or skipped."
    rm -f /tmp/ipfs-desktop.deb
  fi
  
  # install python and flask
  sudo apt install -y python3 python3-pip zip
  pip3 install flask flask-mail requests


# Install the swarm.key into IPFS config
sudo mkdir -p /home/$IPFS_USER/.ipfs
sudo cp "$SWARM_KEY_LOCAL_PATH" /home/$IPFS_USER/.ipfs/swarm.key
sudo chown $IPFS_USER:$IPFS_USER /home/$IPFS_USER/.ipfs/swarm.key
chmod 600 /home/$IPFS_USER/.ipfs/swarm.key
echo "  ✓ swarm.key installed at /home/$IPFS_USER/.ipfs/swarm.key"


}

# 1. Detect and mount 1TB+ SSD
setup_mount() {
  echo -e "\n[1/6] Scanning for external SSD ≥ ${MIN_SIZE_GB}GB..."
  
  # Find block devices excluding root SD card
  DEVICES=$(lsblk -o NAME,SIZE,MOUNTPOINT -d -n | grep -v '/$' | awk '{print "/dev/"$1}')
  
  for DEV in $DEVICES; do
    SIZE_GB=$(lsblk -b -dn -o SIZE "$DEV" | awk '{printf "%.0f", $1 / (1024*1024*1024)}')
    
    if (( SIZE_GB >= MIN_SIZE_GB )); then
      echo "  ✓ Found $DEV with ${SIZE_GB}GB. Mounting..."
      
      # Find partition
      PART="${DEV}1"
      sudo mkdir -p "$MOUNT_POINT"
      sudo mount "$PART" "$MOUNT_POINT"
      
      if [ $? -ne 0 ]; then
        echo "  ❌ Failed to mount $PART"
        exit 1
      fi

      # Persist to fstab
      UUID=$(blkid -s UUID -o value "$PART")
      grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null

      sudo chown -R $IPFS_USER:$IPFS_USER "$MOUNT_POINT"
      echo "  ✓ SSD mounted at $MOUNT_POINT and ready for IPFS."
      return
    fi
  done

  echo "❌ No suitable SSD (≥${MIN_SIZE_GB}GB) found. Aborting."
  exit 1
}

# 2. Configure IPFS systemd service
setup_ipfs_service() {
  echo -e "
[2/6] Setting up IPFS systemd service..."

  sudo -u $IPFS_USER ipfs init --profile=server
  sudo -u $IPFS_USER ipfs config Addresses.API /ip4/127.0.0.1/tcp/5001
  sudo -u $IPFS_USER ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

  # Set custom node name in IPFS config for diagnostics
  sudo -u $IPFS_USER ipfs config --json Identity.NodeName "\"$NODE_NAME\""

  # Advertise public subdomain for peer discovery (optional)
  sudo -u $IPFS_USER ipfs config --json Addresses.Announce \
    "[\"/dns4/${TUNNEL_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}/tcp/443/https\"]"

  cat <<EOF | sudo tee /etc/systemd/system/ipfs.service > /dev/null
[Unit]
Description=IPFS daemon
After=network.target mnt-ipfs.mount
Requires=mnt-ipfs.mount

[Service]
User=$IPFS_USER
ExecStart=/usr/local/bin/ipfs daemon --enable-gc
Restart=on-failure
LimitNOFILE=10240

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable ipfs
  sudo systemctl start ipfs

  echo "  ✓ IPFS service installed and running as '$IPFS_USER' with node name '$NODE_NAME'"
}

# 3. Autostart IPFS Web UI in fullscreen
setup_desktop_launcher() {
echo -e "
[3/6] Setting up IPFS Desktop Web UI autostart..."

 AUTOSTART_DIR="/home/$IPFS_USER/.config/autostart"
  mkdir -p "$AUTOSTART_DIR"

  cat <<EOF | sudo tee "$AUTOSTART_DIR/ipfs-desktop.desktop" > /dev/null
[Desktop Entry]
Name=IPFS Web UI
Exec=chromium-browser --start-fullscreen http://127.0.0.1:5001/webui
Type=Application
X-GNOME-Autostart-enabled=true
EOF

  sudo chown $IPFS_USER:$IPFS_USER "$AUTOSTART_DIR/ipfs-desktop.desktop"
  chmod +x "$AUTOSTART_DIR/ipfs-desktop.desktop"

  echo "  ✓ IPFS Web UI will open in fullscreen at startup."
}

# 4. Install and configure Caddy
setup_caddy() {
  echo -e "\n[4/6] Installing and configuring Caddy reverse proxy..."

  # Hash password
  HASHED_PASS=$(caddy hash-password --plaintext "$ADMIN_PASS")

  # Create Caddyfile
  FULL_DOMAIN="$TUNNEL_SUBDOMAIN.$CLOUDFLARE_DOMAIN"
  CADDYFILE_PATH="/etc/caddy/Caddyfile"
  sudo tee "$CADDYFILE_PATH" > /dev/null <<EOF
$FULL_DOMAIN {
  reverse_proxy 127.0.0.1:5001$AUTH_BLOCK
}
EOF

  sudo chown root:root "$CADDYFILE_PATH"
  sudo systemctl enable caddy
  sudo systemctl restart caddy

  echo "  ✓ Caddy configured for $FULL_DOMAIN with${ENABLE_AUTH:+ optional} HTTPS and reverse proxy."
  }
  
# 5. Install Cloudflare Tunnel
setup_cloudflare_tunnel() {
  echo -e "\n[5/6] Installing and configuring Cloudflare Tunnel..."

  # Authenticate Cloudflare Tunnel
  echo "  → Running cloudflared login. Please authenticate in the browser..."
  sudo cloudflared login

  # Create and configure named tunnel
  TUNNEL_NAME=NODE_NAME
  sudo cloudflared tunnel create "$TUNNEL_NAME"

  # Create config.yml
  mkdir -p /etc/cloudflared
  sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: $TUNNEL_NAME
credentials-file: /root/.cloudflared/${TUNNEL_NAME}.json

ingress:
  - hostname: ${TUNNEL_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}
    service: http://localhost:8081
  - service: http_status:404
EOF

  # Set up systemd service
  sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable cloudflared
  sudo systemctl start cloudflared

  echo "  ✓ Cloudflare Tunnel '$TUNNEL_NAME' is running and secured at https://${TUNNEL_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
}

# 6. Token ZIP server + logging + remote folder
setup_token_server(){
  echo -e "\n[6/6] Setting up token server..."

  # Create necessary directories
  mkdir -p /home/$IPFS_USER/token-server
  mkdir -p $REMOTE_ADMIN_DIR/zips
  mkdir -p $REMOTE_ADMIN_DIR/tokens
  mkdir -p $REMOTE_ADMIN_DIR/logs
  
  # Set ownership and permissions
  ln -sfn $REMOTE_ADMIN_DIR/tokens /home/$IPFS_USER/token-server/tokens
  ln -sfn $REMOTE_ADMIN_DIR/zips /home/$IPFS_USER/token-server/zips
  ln -sfn $REMOTE_ADMIN_DIR/logs /home/$IPFS_USER/token-server/logs

  chown -R $IPFS_USER:$IPFS_USER /home/$IPFS_USER/token-server
  chown -R $IPFS_USER:$IPFS_USER $REMOTE_ADMIN_DIR
  
  echo "  → Downloading server.py and (if primary) generate_token.py..."
  wget -qO /home/$IPFS_USER/token-server/server.py \
    https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/server.py

  if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
    wget -qO /home/$IPFS_USER/token-server/generate_token.py \
      https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/generate_token.py
    chmod +x /home/$IPFS_USER/token-server/generate_token.py
  fi

  chown $IPFS_USER:$IPFS_USER /home/$IPFS_USER/token-server/*.py
  chmod +x /home/$IPFS_USER/token-server/server.py
  
  # Create systemd service for token server
  sudo tee /etc/systemd/system/token-server.service > /dev/null <<EOF
[Unit]
Description=Token ZIP Flask Server
After=network.target ipfs.service
Requires=ipfs.service

[Service]
WorkingDirectory=/home/$IPFS_USER/token-server
ExecStart=/usr/bin/python3 server.py
User=$IPFS_USER
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable token-server
  sudo systemctl start token-server

  echo "  ✓ Token server running at http://<node>:8082"
  if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
    echo "  ✓ Token generator installed."
    echo "    Run: python3 /home/$IPFS_USER/token-server/generate_token.py <folder>"
  fi
}

# 7. Execute full setup
run_all() {
  echo -e "
📦 HI-pfs Setup Script $SETUP_VERSION"

  prerequisites
  setup_mount
  setup_ipfs_service
  setup_desktop_launcher
  setup_caddy
  setup_cloudflare_tunnel
  setup_token_server

  # --- Add Bootstrap Peers ---
	
if [[ "$IS_PRIMARY_NODE" == "n" && -f "$BOOTSTRAP_PEERS_PATH" ]]; then
  echo "🔗 Adding bootstrap peers from:"
  echo "   → $BOOTSTRAP_PEERS_PATH"
  
  while read -r PEER; do
    if [[ "$PEER" == *"/p2p/"* ]]; then
      echo "  → Adding $PEER"
      sudo -u $IPFS_USER ipfs bootstrap add "$PEER"
    fi
  done < "$BOOTSTRAP_PEERS_PATH"

  echo "  ✓ Bootstrap peers added to IPFS config."
elif [[ "$IS_PRIMARY_NODE" == "n" ]]; then
  echo "  ⚠️  No PEERS.txt found. New node may remain isolated."
  echo "    → Expected here: $BOOTSTRAP_PEERS_PATH"
fi

# --- Auto CID Sync from Primary Node ---
if [[ "$IS_PRIMARY_NODE" == "n" ]]; then
  echo "🔄 Setting up CID auto-sync from primary node..."

  read -p "Enter the PRIMARY node's domain (e.g., ipfs0.example.com): " PRIMARY_DOMAIN

  SYNC_SCRIPT="/home/$IPFS_USER/token-server/pull_shared_cids.sh"
  LOG_PATH="/home/$IPFS_USER/token-server/logs/cid-sync.log"
  SHARED_CID_FILE="/home/$IPFS_USER/ipfs-admin/shared-cids.txt"

  sudo tee "$SYNC_SCRIPT" > /dev/null <<EOF
#!/bin/bash
PRIMARY_NODE="https://$PRIMARY_DOMAIN"
TARGET_FILE="$SHARED_CID_FILE"

echo "[CID SYNC] Fetching shared CIDs from \$PRIMARY_NODE..."
mkdir -p \$(dirname "\$TARGET_FILE")
curl -s "\$PRIMARY_NODE:8082/shared-cids.txt" -o "\$TARGET_FILE"

if [[ -s "\$TARGET_FILE" ]]; then
  echo "[CID SYNC] Pinning CIDs..."
  while read -r CID; do
    ipfs pin add "\$CID" 2>/dev/null
  done < "\$TARGET_FILE"
  echo "[CID SYNC] Done."
else
  echo "[CID SYNC] Warning: shared-cids.txt is empty or unreachable."
fi
EOF

  chmod +x "$SYNC_SCRIPT"
  chown $IPFS_USER:$IPFS_USER "$SYNC_SCRIPT"

  echo "  → Installing cron job for periodic CID sync..."
  (sudo -u $IPFS_USER crontab -l 2>/dev/null; echo "*/30 * * * * $SYNC_SCRIPT >> $LOG_PATH 2>&1") | sudo -u $IPFS_USER crontab -

  echo "  ✓ CID auto-sync scheduled every 30 minutes from $PRIMARY_DOMAIN"
fi


  echo -e "
✅ IPFS node is live. Admin uploads in: $REMOTE_ADMIN_DIR"
  echo "   Token generator: python3 /home/$IPFS_USER/token-server/generate_token.py <folder>"
  echo "   Node setup complete with script version: $SETUP_VERSION"
}

run_all
