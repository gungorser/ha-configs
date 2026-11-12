#!/bin/bash
# Creates the nas-data thin LV (NAS and service data) in the pve/data thin pool when it is missing.
# The LV belongs to no VM: its name does not match vm-<id>-*, so Proxmox never deletes it with a VM.
# docker-vm.sh attaches it to VM 110 by its /dev path; the docker VM formats it on first use only.
# Idempotent: an existing LV is never resized, wiped or formatted here (grow it with lvextend).
# Usage (root on the Proxmox host): proxmox/nas-data.sh [size, default 150G]
set -euo pipefail

VG=pve
POOL=data
LV=nas-data
SIZE=${1:-150G}

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

if lvs "$VG/$LV" >/dev/null 2>&1; then
  echo "$VG/$LV exists, left as it is:"
  lvs -o lv_name,lv_size,data_percent,pool_lv "$VG/$LV"
  exit 0
fi

lvs "$VG/$POOL" >/dev/null || { echo "thin pool $VG/$POOL not found"; exit 1; }

# --setactivationskip n: activate on boot like Proxmox's own thin volumes.
lvcreate --thin --virtualsize "$SIZE" --name "$LV" --setactivationskip n "$VG/$POOL"
echo "created /dev/$VG/$LV ($SIZE thin, unformatted)"
lvs -o lv_name,lv_size,data_percent,pool_lv "$VG/$LV"
