# pylint: skip-file
#!/bin/bash
# HI-pfs: Self-Maintenance Script
# Automatically updates system, Kubo (IPFS), cloudflared, and token server.
# Logs actions and sends optional email alerts.

set -e

# Config
USER="${IPFS_USER:-$(whoami)}"
EMAIL="${EMAIL:-compmonks@compmonks.com}"
HOSTNAME=$(hostname)
LOGFILE="/home/$USER/ipfs-admin/logs/maintenance.log"
NEED_REBOOT=0
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "$(dirname "$LOGFILE")"
echo "[$TIMESTAMP] Self-maintenance started on $HOSTNAME" >> "$LOGFILE"

# 1. System update
echo "→ Updating system packages..." >> "$LOGFILE"
sudo apt update -qq && sudo apt upgrade -y >> "$LOGFILE" 2>&1

# 2. Kubo upgrade
echo "→ Checking Kubo version..." >> "$LOGFILE"
if command -v ipfs &>/dev/null; then
  INSTALLED=$(ipfs version | grep -o 'v[0-9.]*')
else
  INSTALLED="none"
fi
LATEST=$(curl -s https://dist.ipfs.tech/kubo/versions | grep -o 'v[0-9.]*' | head -n1)

if [[ "$LATEST" != "$INSTALLED" ]]; then
  echo "→ Installing Kubo $LATEST" >> "$LOGFILE"
  curl -s https://dist.ipfs.tech/kubo/install.sh | sudo bash >> "$LOGFILE" 2>&1
  NEED_REBOOT=1
else
  echo "→ Kubo is already up to date ($INSTALLED)" >> "$LOGFILE"
fi

# 3. cloudflared update
echo "→ Checking cloudflared..." >> "$LOGFILE"
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
  FILE="cloudflared-linux-arm64.deb"
elif [[ "$ARCH" == "armv7l" ]]; then
  FILE="cloudflared-linux-arm.deb"
else
  FILE="cloudflared-linux-amd64.deb"
fi

curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/$FILE" -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb >> "$LOGFILE" 2>&1
NEED_REBOOT=1

# 4. Caddy upgrade
echo "→ Updating Caddy..." >> "$LOGFILE"
sudo apt install --only-upgrade -y caddy >> "$LOGFILE" 2>&1

# 5. Refresh token-server script
SERVER_PY="/home/$USER/token-server/server.py"
curl -fsSL https://raw.githubusercontent.com/compmonks/HI-pfs/main/scripts/server.py -o "$SERVER_PY.new"

if ! cmp -s "$SERVER_PY" "$SERVER_PY.new"; then
  mv "$SERVER_PY.new" "$SERVER_PY"
  chmod +x "$SERVER_PY"
  echo "→ Updated server.py to latest version" >> "$LOGFILE"
  NEED_REBOOT=1
else
  rm -f "$SERVER_PY.new"
fi

# 6. Email report
if command -v mail &> /dev/null; then
  echo "📬 Sending maintenance log to $EMAIL..." >> "$LOGFILE"
  mail -s "HI-pfs Maintenance Report ($HOSTNAME)" "$EMAIL" < "$LOGFILE"
fi

# 7. Reboot if needed
if [[ "$NEED_REBOOT" -eq 1 ]]; then
  echo "→ Rebooting due to updates..." >> "$LOGFILE"
  sudo reboot
fi

echo "[$TIMESTAMP] Self-maintenance completed." >> "$LOGFILE"
