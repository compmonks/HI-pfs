# pylint: skip-file
#!/bin/bash
# Check if primary node is alive; promote self if needed

USER="${IPFS_USER:-$(whoami)}"
ROLE_FILE="/home/$USER/ipfs-admin/role.txt"
HEARTBEAT="/home/$USER/ipfs-admin/heartbeat.log"
THRESHOLD=180  # 3 minutes
NOW=$(date +%s)

mkdir -p "/home/$USER/ipfs-admin"

if [[ ! -f "$ROLE_FILE" ]]; then
  echo "secondary" > "$ROLE_FILE"
fi

ROLE=$(cat "$ROLE_FILE")
LAST=$(cat "$HEARTBEAT" 2>/dev/null || echo 0)
DIFF=$((NOW - LAST))

if [[ "$ROLE" == "secondary" && "$DIFF" -gt "$THRESHOLD" ]]; then
  echo "🛑 No heartbeat in $DIFF seconds. Promoting..."
  bash /home/$USER/scripts/promote.sh
fi