#!/bin/bash
# HI-pfs Pull Shared CIDs Script
# Description: Fetches shared-cids.txt from the primary node and pins any new CIDs on secondary nodes

set -euo pipefail

# Source environment variables
[ -f /etc/hi-pfs.env ] && . /etc/hi-pfs.env

# Only run on secondary nodes
if [[ "${IS_PRIMARY_NODE:-}" == "y" ]]; then
  exit 0
fi

PRIMARY_HOST="ipfs-node-00"
# If primary host is not reachable, try .local domain
if ! ping -c1 -W2 "$PRIMARY_HOST" &>/dev/null; then
  if ! ping -c1 -W2 "${PRIMARY_HOST}.local" &>/dev/null; then
    echo "❌ Primary host '$PRIMARY_HOST' unreachable. Edit script to set the correct address."
    exit 1
  else
    PRIMARY_HOST="${PRIMARY_HOST}.local"
  fi
fi

PRIMARY_URL="http://$PRIMARY_HOST:8082/shared-cids.txt"
TMP_FILE="$(mktemp)"

if ! curl -fsSL "$PRIMARY_URL" -o "$TMP_FILE"; then
  echo "❌ Failed to download shared-cids list from primary ($PRIMARY_URL)"
  rm -f "$TMP_FILE"
  exit 1
fi

LOCAL_FILE="/home/$IPFS_USER/ipfs-admin/shared-cids.txt"
LOG_FILE="/home/$IPFS_USER/ipfs-admin/logs/cid-pin.log"
mkdir -p "$(dirname "$LOG_FILE")"

if [[ ! -f "$LOCAL_FILE" ]]; then
  new_cids=$(cat "$TMP_FILE")
else
  # Determine new CIDs that are not already pinned locally
  new_cids=$(comm -13 <(sort "$LOCAL_FILE") <(sort "$TMP_FILE"))
fi

if [[ -z "$new_cids" ]]; then
  rm -f "$TMP_FILE"
  exit 0
fi

while IFS= read -r cid; do
  [[ -z "$cid" ]] && continue
  if sudo -u "$IPFS_USER" IPFS_PATH=/mnt/ipfs/ipfs-data ipfs pin add "$cid" > /dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pinned $cid" >> "$LOG_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to pin $cid" >> "$LOG_FILE"
  fi
done < <(printf "%s\n" "$new_cids")

mv "$TMP_FILE" "$LOCAL_FILE"
chown "$IPFS_USER:$IPFS_USER" "$LOCAL_FILE"
