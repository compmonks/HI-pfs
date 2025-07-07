#!/bin/bash
# IPFS Raspberry Pi Node Setup with Secure Remote Admin, Token-Gated ZIP Delivery, Dropbox Log Sync, and Replication Readiness

MOUNT_POINT="/mnt/ipfs"
MIN_SIZE_GB=990
IPFS_PATH="$MOUNT_POINT/ipfs-data"
REMOTE_ADMIN_DIR="/home/$IPFS_USER/ipfs-admin"
DROPBOX_LOG_DIR="/home/$IPFS_USER/Dropbox/IPFS-Logs"
SETUP_VERSION="v1.0.0"

read -p "Enter your Pi admin/user name: " IPFS_USER
read -p "Enter your email for reports: " EMAIL
read -p "Enter your desired Cloudflare Tunnel subdomain (e.g., mynode): " TUNNEL_SUBDOMAIN

# 1. Detect and mount 1TB+ SSD
setup_mount() {
  echo -e "\n[1/6] Scanning for external SSD ≥ ${MIN_SIZE_GB}GB..."
  
  # Find block devices excluding root SD card
  DEVICES=$(lsblk -o NAME,SIZE,MOUNTPOINT -d -n | grep -v '/$' | awk '{print "/dev/"$1}')
  
  for DEV in $DEVICES; do
    SIZE_GB=$(lsblk -b -dn -o SIZE "$DEV" | awk '{printf "%.0f", $1 / (1024*1024*1024)}')
    
    if (( SIZE_GB >= MIN_SIZE_GB )); then
      echo "  ✓ Found $DEV with ${SIZE_GB}GB. Mounting..."
      
      # Find partition
      PART="${DEV}1"
      sudo mkdir -p "$MOUNT_POINT"
      sudo mount "$PART" "$MOUNT_POINT"
      
      if [ $? -ne 0 ]; then
        echo "  ❌ Failed to mount $PART"
        exit 1
      fi

      # Persist to fstab
      UUID=$(blkid -s UUID -o value "$PART")
      grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null

      sudo chown -R $IPFS_USER:$IPFS_USER "$MOUNT_POINT"
      echo "  ✓ SSD mounted at $MOUNT_POINT and ready for IPFS."
      return
    fi
  done

  echo "❌ No suitable SSD (≥${MIN_SIZE_GB}GB) found. Aborting."
  exit 1
}
