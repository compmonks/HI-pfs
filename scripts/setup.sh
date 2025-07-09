#!/bin/bash
# HI-pfs Full Node Setup Script
# Configures Raspberry Pi with IPFS, Cloudflare, Caddy, and CID replication

set -e

### 0. VERIFY INPUT ENVIRONMENT VARIABLES
REQUIRED_VARS=(IPFS_USER EMAIL NODE_NAME TUNNEL_SUBDOMAIN CLOUDFLARE_DOMAIN IS_PRIMARY_NODE MIN_SIZE_GB)
for VAR in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!VAR}" ]]; then
    echo "❌ Missing environment variable: $VAR. Run via bootstrap.sh or export manually."
    exit 1
  fi
done

### 1. GLOBAL CONFIG
MOUNT_POINT="/mnt/ipfs"
IPFS_PATH="$MOUNT_POINT/ipfs-data"
REMOTE_ADMIN_DIR="/home/$IPFS_USER/ipfs-admin"
SETUP_VERSION="v1.1.0"

### 2. PREREQUISITES
prerequisites() {
  echo "[0/6] Installing prerequisites..."
  sudo apt update
  sudo apt install -y curl unzip python3 python3-pip zip cron mailutils

  if ! command -v ipfs &>/dev/null; then
    curl -s https://dist.ipfs.tech/go-ipfs/install.sh | sudo bash
  fi

  if ! command -v caddy &>/dev/null; then
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install -y caddy
  fi

  if ! command -v chromium-browser &>/dev/null; then
    sudo apt install -y chromium-browser
  fi

  pip3 install flask flask-mail requests
}

### 3. SSD MOUNT
setup_mount() {
  echo "[1/6] Mounting SSD..."
  DEV=$(lsblk -dnpo NAME,SIZE | awk -v min=$((MIN_SIZE_GB * 1024**3)) '$2+0 >= min {print $1; exit}')
  [[ -z "$DEV" ]] && echo "❌ No ≥$MIN_SIZE_GB GB device found" && exit 1
  PART="${DEV}1"
  sudo mkdir -p "$MOUNT_POINT"
  sudo mount "$PART" "$MOUNT_POINT" || exit 1
  UUID=$(blkid -s UUID -o value "$PART")
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null
  sudo chown -R $IPFS_USER:$IPFS_USER "$MOUNT_POINT"
}

### 4. IPFS SYSTEMD SERVICE
setup_ipfs_service() {
  echo "[2/6] IPFS config and daemon setup..."
  sudo -u $IPFS_USER ipfs init --profile=server
  sudo -u $IPFS_USER ipfs config Addresses.API /ip4/127.0.0.1/tcp/5001
  sudo -u $IPFS_USER ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080
  sudo -u $IPFS_USER ipfs config --json Identity.NodeName \"$NODE_NAME\"
  sudo -u $IPFS_USER ipfs config --json Addresses.Announce \"[\"/dns4/${TUNNEL_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}/tcp/443/https\"]\"

  sudo tee /etc/systemd/system/ipfs.service > /dev/null <<EOF
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
}

### 5. AUTOSTART IPFS DESKTOP UI
setup_desktop_launcher() {
  echo "[3/6] Configuring IPFS Desktop UI launch..."
  mkdir -p "/home/$IPFS_USER/.config/autostart"
  sudo tee "/home/$IPFS_USER/.config/autostart/ipfs-desktop.desktop" > /dev/null <<EOF
[Desktop Entry]
Name=IPFS Web UI
Exec=chromium-browser --start-fullscreen http://127.0.0.1:5001/webui
Type=Application
X-GNOME-Autostart-enabled=true
EOF
  sudo chown $IPFS_USER:$IPFS_USER "/home/$IPFS_USER/.config/autostart/ipfs-desktop.desktop"
  chmod +x "/home/$IPFS_USER/.config/autostart/ipfs-desktop.desktop"
}

### 6. CADDY CONFIG
setup_caddy() {
  echo "[4/6] Configuring Caddy..."
  read -p "Enable password protection for Web UI? (y/n): " ENABLE_AUTH
  if [[ "$ENABLE_AUTH" == "y" ]]; then
    read -s -p "Enter password for $IPFS_USER: " ADMIN_PASS && echo
    HASHED_PASS=$(caddy hash-password --plaintext "$ADMIN_PASS")
    AUTH_BLOCK="\n  basicauth {\n    $IPFS_USER $HASHED_PASS\n  }"
  else
    AUTH_BLOCK=""
  fi
  sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
$TUNNEL_SUBDOMAIN.$CLOUDFLARE_DOMAIN {
  reverse_proxy 127.0.0.1:5001$AUTH_BLOCK
}
EOF
  sudo systemctl enable caddy
  sudo systemctl restart caddy
}

### 7. TOKEN SERVER
setup_token_server() {
  echo "[5/6] Installing token server..."
  mkdir -p /home/$IPFS_USER/token-server
  mkdir -p $REMOTE_ADMIN_DIR/{zips,tokens,logs}
  ln -sfn $REMOTE_ADMIN_DIR/zips /home/$IPFS_USER/token-server/zips
  ln -sfn $REMOTE_ADMIN_DIR/tokens /home/$IPFS_USER/token-server/tokens
  ln -sfn $REMOTE_ADMIN_DIR/logs /home/$IPFS_USER/token-server/logs

  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/server.py -o /home/$IPFS_USER/token-server/server.py
  if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
    curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/generate_token.py -o /home/$IPFS_USER/token-server/generate_token.py
    chmod +x /home/$IPFS_USER/token-server/generate_token.py
  fi
  chmod +x /home/$IPFS_USER/token-server/server.py
  chown -R $IPFS_USER:$IPFS_USER /home/$IPFS_USER/token-server

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
}

### 8. CID SYNC SETUP
setup_cid_sync() {
  mkdir -p /home/$IPFS_USER/scripts

  if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
    cat <<EOF | sudo tee /home/$IPFS_USER/scripts/cid_autosync.sh > /dev/null
#!/bin/bash
CID_FILE="/home/$IPFS_USER/ipfs-admin/shared-cids.txt"
LOG="/home/$IPFS_USER/ipfs-admin/logs/cid-sync.log"
TMP_CIDS="/tmp/pinned_now.txt"
mkdir -p 