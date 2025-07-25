# pylint: skip-file
#!/bin/bash
# =============================================================================
# HI-pfs: Full Node Setup Script
# Sets up IPFS node with gateway load balancing, automatic CID/token management,
# secure reverse proxy, and dynamic role switching (primary/secondary)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

### 0. VERIFY INPUT ENVIRONMENT VARIABLES
REQUIRED_VARS=(IPFS_USER EMAIL NODE_NAME TUNNEL_SUBDOMAIN CLOUDFLARE_DOMAIN IS_PRIMARY_NODE SSD_DEVICE)
echo "🔍 Verifying environment variables..."
for VAR in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!VAR:-}" ]]; then
    echo "❌ Missing environment variable: $VAR. Run via bootstrap.sh or export manually."
    exit 1
  else
    echo "✓ $VAR = ${!VAR}"
  fi
done

### 1. GLOBAL CONFIG
MOUNT_POINT="/mnt/ipfs"
IPFS_PATH="$MOUNT_POINT/ipfs-data"
REMOTE_ADMIN_DIR="/home/$IPFS_USER/ipfs-admin"
SETUP_VERSION="v1.3.0"
echo "🌍 Detected setup version: $SETUP_VERSION"

### 2. PREREQUISITES
prerequisites() {
  echo "[0/6] Installing prerequisites..."

  # Ensure Kubo (ipfs CLI) is installed beforehand
  if ! command -v ipfs &>/dev/null; then
    echo "→ Kubo not found. Installing..."
    KUBO_VERSION="v0.36.0"
    KUBO_URL="https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_linux-arm64.tar.gz"
    echo "ℹ️ Using Kubo ${KUBO_VERSION}. Check https://dist.ipfs.tech/kubo/ for newer releases."
    curl -L "$KUBO_URL" -o /tmp/kubo.tar.gz || {
      echo "❌ Failed to download Kubo." >&2
      exit 1
    }
    tar -xzf /tmp/kubo.tar.gz -C /tmp
    sudo bash /tmp/kubo/install.sh || {
      echo "❌ Kubo install failed." >&2
      exit 1
    }
    rm -rf /tmp/kubo /tmp/kubo.tar.gz
  fi
  echo "✓ Kubo detected: $(ipfs version)"

  sudo apt update
  sudo apt install -y curl unzip python3 python3-pip zip cron mailutils inotify-tools lsb-release parted exfat-fuse exfatprogs ntfs-3g
  # Remove any packages that are no longer required after installation
  sudo apt autoremove -y

  if ! command -v caddy &>/dev/null; then
    echo "→ Installing Caddy (HTTPS reverse proxy)..."
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    sudo apt autoremove -y
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install -y caddy
    sudo apt autoremove -y
  fi

  if ! command -v chromium-browser &>/dev/null; then
    echo "→ Installing Chromium for desktop WebUI..."
    sudo apt install -y chromium-browser
    sudo apt autoremove -y
  fi

  # Handle Debian's PEP 668 "externally-managed" environment
  pip3 install --break-system-packages flask flask-mail requests
}

### 3. SSD MOUNT
setup_mount() {
  echo "💽 Mounting SSD at ${SSD_DEVICE}..."
  DEV="$SSD_DEVICE"
  if [[ ! -b "$DEV" ]]; then
    echo "❌ Device $DEV not found"
    echo "📂 Available devices:"
    lsblk -dnpo NAME,SIZE,TYPE | awk '$3=="disk"{printf "  %s (%s)\n", $1, $2}'
    read -rp "🤔 Enter device path to use for the SSD (or press Enter to abort): " DEV
    if [[ -z "$DEV" ]]; then
      echo "Aborting mount setup."
      exit 1
    fi
  fi

  while true; do
    PART=$(lsblk -lnpo NAME,TYPE "$DEV" | awk '$2=="part"{print $1; exit}')
    [[ -z "$PART" ]] && PART="$DEV"

    FSTYPE=$(lsblk -no FSTYPE "$PART" | head -n 1)
    [[ -z "$FSTYPE" ]] && FSTYPE=$(blkid -s TYPE -o value "$PART" 2>/dev/null || true)
    if [[ -z "$FSTYPE" ]]; then
      echo "→ Formatting $PART as ntfs..."
      sudo mkfs.ntfs -F "$PART"
      FSTYPE="ntfs"
    else
      case "$FSTYPE" in
        ntfs|ext4|exfat)
          echo "✓ Detected filesystem: $FSTYPE"
          ;;
        *)
          echo "⚠️ Unsupported filesystem $FSTYPE. Reformatting as ntfs..."
          sudo mkfs.ntfs -F "$PART"
          FSTYPE="ntfs"
          ;;
      esac
    fi

    sudo mkdir -p "$MOUNT_POINT"
    if sudo mount -t "$FSTYPE" "$PART" "$MOUNT_POINT"; then
      break
    fi

    echo "❌ Failed to mount $PART"
    echo "📂 Available devices:"
    lsblk -dnpo NAME,SIZE,TYPE | awk '$3=="disk"{printf "  %s (%s)\n", $1, $2}'
    read -rp "Enter different device path to retry (or press Enter to abort): " DEV
    if [[ -z "$DEV" ]]; then
      echo "Aborting mount setup."
      exit 1
    fi
  done

  UUID=$(blkid -s UUID -o value "$PART")
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT $FSTYPE defaults,nofail,x-systemd.requires=network-online.target 0 2" | sudo tee -a /etc/fstab > /dev/null
  sudo chown -R $IPFS_USER:$IPFS_USER "$MOUNT_POINT"
  mkdir -p "$IPFS_PATH"
  sudo chown -R $IPFS_USER:$IPFS_USER "$IPFS_PATH"
  echo "✓ SSD mounted at $MOUNT_POINT"
}

### 4. IPFS SYSTEMD SERVICE
setup_ipfs_service() {
  echo "[2/6] Validating IPFS installation and setting up service..."

  # Check IPFS binary
  if ! command -v ipfs &>/dev/null; then
    echo "❌ IPFS command not found. Reinstalling..."
    KUBO_VERSION="v0.36.0"
    KUBO_URL="https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_linux-arm64.tar.gz"
    echo "ℹ️ Using Kubo ${KUBO_VERSION}. Check https://dist.ipfs.tech/kubo/ for newer releases."
    curl -L "$KUBO_URL" -o /tmp/kubo.tar.gz || {
      echo "❌ Failed to download Kubo." >&2
      return 1
    }
    tar -xzf /tmp/kubo.tar.gz -C /tmp
    if ! sudo bash /tmp/kubo/install.sh; then
      echo "❌ Kubo install failed." >&2
      return 1
    fi
    rm -rf /tmp/kubo /tmp/kubo.tar.gz
    if ! command -v ipfs &>/dev/null; then
      echo "❌ Kubo install failed." >&2
      return 1
    fi
  else
    echo "✓ IPFS installed: $(ipfs version)"
  fi

  # Ensure .ipfs config exists
  if [[ ! -f "$IPFS_PATH/config" ]]; then
    echo "⚙️ Initializing IPFS config for $IPFS_USER..."
    sudo -u $IPFS_USER IPFS_PATH="$IPFS_PATH" ipfs init --profile=server
  fi

  # Double-check that mount exists
  if [[ ! -d "$MOUNT_POINT" || ! -d "$IPFS_PATH" ]]; then
    echo "❌ /mnt/ipfs or its subfolder is missing. SSD might not be mounted properly."
    echo "Aborting IPFS service setup until mount issue is resolved."
    return 1
  fi

  echo "🔧 Applying IPFS configurations..."
  sudo -u $IPFS_USER IPFS_PATH="$IPFS_PATH" ipfs config Addresses.API /ip4/127.0.0.1/tcp/5001
  sudo -u $IPFS_USER IPFS_PATH="$IPFS_PATH" ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

  # Older IPFS versions (e.g., 0.36) do not support Identity.NodeName
  if sudo -u $IPFS_USER IPFS_PATH="$IPFS_PATH" ipfs config Identity.NodeName >/dev/null 2>&1; then
    sudo -u $IPFS_USER IPFS_PATH="$IPFS_PATH" ipfs config --json Identity.NodeName "\"$NODE_NAME\""
  else
    echo "⚠️  Identity.NodeName unsupported in this IPFS version, skipping"
  fi

  sudo -u $IPFS_USER IPFS_PATH="$IPFS_PATH" ipfs config --json Addresses.Announce "[\"/dns4/${TUNNEL_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}/tcp/443/https\"]"

  echo "📝 Creating IPFS systemd service..."
  sudo tee /etc/systemd/system/ipfs.service > /dev/null <<EOF
[Unit]
Description=IPFS daemon
After=network.target mnt-ipfs.mount
Requires=mnt-ipfs.mount

[Service]
User=$IPFS_USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="IPFS_PATH=$IPFS_PATH"
ExecStart=/usr/local/bin/ipfs daemon --enable-gc
Restart=on-failure
LimitNOFILE=10240

[Install]
WantedBy=multi-user.target
EOF

  echo "🔄 Reloading systemd and enabling IPFS service..."
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable ipfs
  sudo systemctl restart ipfs

  sleep 2
  if systemctl is-active --quiet ipfs; then
    echo "✅ IPFS service is running."
  else
    echo "❌ IPFS service failed to start. Check logs with: journalctl -u ipfs -e"
  fi
}

### 5. AUTO TOKEN WATCHER
setup_auto_token_generator() {
  echo "[6/6] Setting up automatic token generation watcher..."

  mkdir -p /home/$IPFS_USER/token-server
  cd /home/$IPFS_USER/token-server

  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/server.py -o server.py
  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/generate_token.py -o generate_token.py
  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/regenerate_token.py -o regenerate_token.py

  chmod +x *.py
  chown -R $IPFS_USER:$IPFS_USER /home/$IPFS_USER/token-server

  echo "✓ Token server scripts downloaded and permissioned."

  WATCH_SCRIPT="/home/$IPFS_USER/scripts/auto_token_watch.sh"
  SERVICE_FILE="/etc/systemd/system/auto-token.service"
  LOG_FILE="/home/$IPFS_USER/ipfs-admin/logs/auto-token.log"
  WATCH_DIR="/home/$IPFS_USER/ipfs-admin/uploads"

  mkdir -p "/home/$IPFS_USER/scripts" "/home/$IPFS_USER/ipfs-admin/uploads" "$(dirname $LOG_FILE)"

  cat <<'EOSH' | tee "$WATCH_SCRIPT" > /dev/null
#!/bin/bash
WATCH_DIR="$WATCH_DIR"
LOG_FILE="$LOG_FILE"
GEN_SCRIPT="/home/$IPFS_USER/token-server/generate_token.py"
EMAIL="$EMAIL"

inotifywait -m -r -e create --format '%w%f' "$WATCH_DIR" | while read newfile; do
  if [[ -d "$newfile" ]]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] New folder detected: $newfile" >> "$LOG_FILE"

    OUTPUT=$(python3 "$GEN_SCRIPT" "$newfile")
    echo "$OUTPUT" >> "$LOG_FILE"

    echo -e "New Token Generated on $HOSTNAME\n\n$OUTPUT" | mail -s "HI-pfs Token Created" "$EMAIL"
  fi
done
EOSH

  chmod +x "$WATCH_SCRIPT"
  chown $IPFS_USER:$IPFS_USER "$WATCH_SCRIPT"

  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=HI-pfs Auto Token Generator
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $WATCH_SCRIPT
Restart=always
User=$IPFS_USER

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable auto-token.service
  sudo systemctl start auto-token.service
  echo "✓ Auto-token watcher enabled for uploads directory."
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
    AUTH_BLOCK="  basicauth {\n    $IPFS_USER $HASHED_PASS\n  }\n"
  else
    AUTH_BLOCK=""
  fi

  echo "→ Support multiple upstream nodes for load balancing? (e.g. ipfs1.local, ipfs2.local)"
  read -p "Comma-separated upstream IPFS API hosts or leave blank: " GATEWAY_BACKENDS

  GATEWAY_BLOCK=""
  if [[ -n "$GATEWAY_BACKENDS" ]]; then
    BACKENDS=""
    IFS=',' read -ra NODES <<< "$GATEWAY_BACKENDS"
    for NODE in "${NODES[@]}"; do
      BACKENDS+="  reverse_proxy $NODE:5001\n"
    done
    GATEWAY_BLOCK="/gateway {\n${BACKENDS}}\n"
  fi

  FULL_DOMAIN="$TUNNEL_SUBDOMAIN.$CLOUDFLARE_DOMAIN"
  CADDY_CONFIG="$FULL_DOMAIN {\n\n"
  if [[ -n "$AUTH_BLOCK" ]]; then
    CADDY_CONFIG+="$AUTH_BLOCK"
  fi
  CADDY_CONFIG+="  reverse_proxy 127.0.0.1:5001\n\n}\n"
  if [[ -n "$GATEWAY_BLOCK" ]]; then
    CADDY_CONFIG+="\n$GATEWAY_BLOCK"
  fi
  printf "%b" "$CADDY_CONFIG" | sudo tee /etc/caddy/Caddyfile > /dev/null

  sudo systemctl enable caddy
  sudo systemctl restart caddy
  if [[ -n "$GATEWAY_BACKENDS" ]]; then
    echo "✓ Caddy configured with Web UI at $FULL_DOMAIN and gateway /gateway endpoint."
  else
    echo "✓ Caddy configured with Web UI at $FULL_DOMAIN"
  fi
}

### 7. TOKEN SERVER
setup_token_server() {
  echo "[5/6] Installing token server..."
  mkdir -p /home/$IPFS_USER/token-server
  mkdir -p "$REMOTE_ADMIN_DIR"/{zips,tokens,logs}
  sudo chown -R $IPFS_USER:$IPFS_USER "$REMOTE_ADMIN_DIR"
  echo "${IS_PRIMARY_NODE}" > "$REMOTE_ADMIN_DIR/role.txt"
  ln -sfn $REMOTE_ADMIN_DIR/zips /home/$IPFS_USER/token-server/zips
  ln -sfn $REMOTE_ADMIN_DIR/tokens /home/$IPFS_USER/token-server/tokens
  ln -sfn $REMOTE_ADMIN_DIR/logs /home/$IPFS_USER/token-server/logs

  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/server.py -o /home/$IPFS_USER/token-server/server.py
  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/generate_token.py -o /home/$IPFS_USER/token-server/generate_token.py
  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/regenerate_token.py -o /home/$IPFS_USER/token-server/regenerate_token.py
  chmod +x /home/$IPFS_USER/token-server/*.py
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
deploy_cid_sync() {
  if [[ "$IS_PRIMARY_NODE" == "y" ]]; then
    echo "[6/6] Enabling autosync on primary node..."
    local SCRIPT_FILE="/home/$IPFS_USER/scripts/cid-autosync.sh"
    local SERVICE_FILE="/etc/systemd/system/cid-autosync.service"
    local TIMER_FILE="/etc/systemd/system/cid-autosync.timer"

    if [[ ! -f "$SCRIPT_FILE" ]]; then
      cat <<'EOSH' | sudo tee "$SCRIPT_FILE" > /dev/null
#!/bin/bash
USER="${IPFS_USER:-$(whoami)}"
CID_FILE="/home/$USER/ipfs-admin/shared-cids.txt"
LOG_FILE="/home/$USER/ipfs-admin/logs/cid-sync.log"

mkdir -p "$(dirname "$CID_FILE")" "$(dirname "$LOG_FILE")"
ipfs pin ls --type=recursive -q > "$CID_FILE"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] CID list synced" >> "$LOG_FILE"
EOSH
      sudo chmod +x "$SCRIPT_FILE"
      sudo chown $IPFS_USER:$IPFS_USER "$SCRIPT_FILE"
    fi

    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=HI-pfs CID Autosync
After=network-online.target ipfs.service
Requires=ipfs.service

[Service]
Type=oneshot
EnvironmentFile=/etc/hi-pfs.env
ExecStart=$SCRIPT_FILE
User=$IPFS_USER

[Install]
WantedBy=multi-user.target
EOF

    sudo tee "$TIMER_FILE" > /dev/null <<EOF
[Unit]
Description=Run CID autosync hourly

[Timer]
OnBootSec=10min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable cid-autosync.timer
    sudo systemctl start cid-autosync.timer
  else
    echo "[6/6] Pulling shared CIDs from primary..."
    curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/pull_shared_cids.sh -o /home/$IPFS_USER/scripts/pull_shared_cids.sh
    chmod +x /home/$IPFS_USER/scripts/pull_shared_cids.sh
    (crontab -l 2>/dev/null; echo "*/10 * * * * /home/$IPFS_USER/scripts/pull_shared_cids.sh") | crontab -
  fi
}

finalize_setup() {
  echo -e "\n🔍 Running final diagnostics and tests..."

  echo "→ Checking IPFS repo version..."
  if ! ipfs repo stat >/dev/null 2>&1; then
    echo "⚠️ IPFS repo requires migration. Running migration..."
    sudo systemctl stop ipfs
    ipfs daemon --migrate=true >/tmp/ipfs_migrate.log 2>&1 &
    PID=$!
    sleep 15
    kill "$PID" >/dev/null 2>&1 || true
    sudo systemctl start ipfs
  else
    echo "✓ IPFS repo is current."
  fi

  for svc in ipfs cloudflared caddy token-server; do
    if ! systemctl is-active --quiet "$svc"; then
      echo "↪ Restarting $svc..."
      sudo systemctl restart "$svc"
    fi
  done

  sudo -u $IPFS_USER bash /home/$IPFS_USER/scripts/diagnostics.sh
  TMP_TEST_DIR="/tmp/hi-pfs-tests"
  mkdir -p "$TMP_TEST_DIR"
  curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/tests/test_server.py -o "$TMP_TEST_DIR/test_server.py"
  if ! command -v pytest >/dev/null; then
    echo "Installing pytest for tests..."
    pip3 install --break-system-packages pytest >/dev/null 2>&1
  fi
  sudo -u $IPFS_USER pytest "$TMP_TEST_DIR/test_server.py"
}

### 9. EXECUTE
run_all() {
  echo "\n🚀 Starting HI-pfs Full Node Setup v$SETUP_VERSION"
  prerequisites
  setup_mount
  setup_ipfs_service
  setup_auto_token_generator
  setup_desktop_launcher
  setup_caddy
  setup_token_server
  deploy_cid_sync
  finalize_setup
  echo -e "\n✅ Node setup complete. Admin dir: $REMOTE_ADMIN_DIR"
}

run_all
