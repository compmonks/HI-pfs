#!/bin/bash
# Optional: Demote current primary node to secondary

USER="${IPFS_USER:-$(whoami)}"
ROLE_FILE="/home/$USER/ipfs-admin/role.txt"
LOG="/home/$USER/ipfs-admin/logs/demotion.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "/home/$USER/ipfs-admin/logs"
echo "[$TIMESTAMP] Demoting node to SECONDARY" >> "$LOG"
echo "secondary" > "$ROLE_FILE"

# Disable CID autosync
sudo systemctl stop cid-autosync.timer
sudo systemctl disable cid-autosync.timer

# Optional: Send alert
if command -v mail &>/dev/null; then
  echo -e "Node demoted to SECONDARY at $TIMESTAMP\nHostname: $(hostname)" | \
  mail -s "HI-pfs DEMOTION: $(hostname)" "$EMAIL"
fi