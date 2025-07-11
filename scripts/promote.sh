# pylint: skip-file
#!/bin/bash
# Promote this node from secondary to primary

USER="${IPFS_USER:-$(whoami)}"
ROLE_FILE="/home/$USER/ipfs-admin/role.txt"
LOG="/home/$USER/ipfs-admin/logs/promotion.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "/home/$USER/ipfs-admin/logs"
echo "[$TIMESTAMP] Promoting node to PRIMARY" >> "$LOG"

echo "primary" > "$ROLE_FILE"

# Enable CID autosync
sudo systemctl enable cid-autosync.timer
sudo systemctl start cid-autosync.timer

# Enable token generator if exists
if [[ -f "/home/$USER/token-server/generate_token.py" ]]; then
  chmod +x /home/$USER/token-server/generate_token.py
  echo "Token generator enabled" >> "$LOG"
fi

# Optional: Send email alert
if command -v mail &>/dev/null; then
  echo -e "Node promoted to PRIMARY at $TIMESTAMP\nHostname: $(hostname)" | \
  mail -s "HI-pfs PROMOTION: $(hostname)" "$EMAIL"
fi

echo "Promotion complete. Node is now PRIMARY." >> "$LOG"