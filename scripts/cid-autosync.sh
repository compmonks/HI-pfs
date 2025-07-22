#!/bin/bash
# Update list of pinned CIDs for other nodes

USER="${IPFS_USER:-$(whoami)}"
CID_FILE="/home/$USER/ipfs-admin/shared-cids.txt"
LOG_FILE="/home/$USER/ipfs-admin/logs/cid-sync.log"

mkdir -p "$(dirname "$CID_FILE")" "$(dirname "$LOG_FILE")"

ipfs pin ls --type=recursive -q > "$CID_FILE"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] CID list synced" >> "$LOG_FILE"

