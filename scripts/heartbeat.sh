#!/bin/bash
# Update heartbeat file regularly (primary node only)

USER="${IPFS_USER:-$(whoami)}"
HEARTBEAT="/home/$USER/ipfs-admin/heartbeat.log"

mkdir -p "$(dirname "$HEARTBEAT")"
echo $(date +%s) > "$HEARTBEAT"