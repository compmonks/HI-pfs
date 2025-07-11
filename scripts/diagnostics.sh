# pylint: skip-file
#!/bin/bash
# HI-pfs diagnostics: run with `bash diagnostics.sh` or `hi-pfs status`

USER="${IPFS_USER:-$(whoami)}"
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
LOG_DIR="/home/$USER/ipfs-admin/logs"

echo "================ HI-pfs Node Diagnostics ================"
echo "🖥  Hostname:   $HOSTNAME"
echo "🌐 IP Addr:    $IP"
echo "🕒 Uptime:     $(uptime -p)"
echo "💽 Disk usage: $(df -h /mnt/ipfs | tail -1 | awk '{print $5}') used on /mnt/ipfs"
echo

# IPFS info
echo "🔌 IPFS Status:"
systemctl is-active ipfs >/dev/null && echo "✅ ipfs.service is running." || echo "❌ ipfs.service is NOT running!"
echo "🔢 IPFS version: $(ipfs version | cut -d ' ' -f3)"
echo "🧩 Swarm peers: $(ipfs swarm peers | wc -l)"
echo

# Tunnel / reverse proxy
echo "🌍 Reverse Proxy:"
systemctl is-active cloudflared >/dev/null && echo "✅ cloudflared is active" || echo "❌ cloudflared is DOWN"
systemctl is-active caddy >/dev/null && echo "✅ Caddy is active" || echo "❌ Caddy is DOWN"
echo

# Pinned content
echo "📦 Pinned CIDs: $(ipfs pin ls --type=recursive | wc -l)"
echo "🔑 swarm.key present? $(test -f /home/$USER/.ipfs/swarm.key && echo Yes || echo No)"
echo "📁 shared-cids.txt present? $(test -f /home/$USER/ipfs-admin/shared-cids.txt && echo Yes || echo No)"
echo "📁 PEERS.txt present? $(test -f /home/$USER/PEERS.txt && echo Yes || echo No)"
echo

# Last logs
if [[ -f "$LOG_DIR/cid-sync.log" ]]; then
  echo "📋 Last CID Sync:"
  tail -n 3 "$LOG_DIR/cid-sync.log"
  echo
fi

if [[ -f "$LOG_DIR/access.log" ]]; then
  echo "📥 Recent Token Downloads:"
  grep 'ACCEPTED' "$LOG_DIR/access.log" | tail -n 3
  echo
fi

echo "========================================================="