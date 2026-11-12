#!/bin/bash
# Creates the NAS thin LVs in the pve/data thin pool when they are missing. They belong to no VM:
# their names do not match vm-<id>-*, so Proxmox never deletes them with a VM. docker-vm.sh attaches
# them to VM 110 by their /dev path (scsi1..scsi4, same order as below); the docker-host area
# formats an empty one only when told to, and mounts them by UUID.
# Idempotent: an existing LV is never resized, wiped or formatted here (grow it with lvextend,
# then resize2fs in the VM).
# Usage (root on the Proxmox host): proxmox/nas-disks.sh
set -euo pipefail

VG=pve
POOL=data
# name:size  (scsi1..scsi4 in docker-vm.sh, mount points in docker-host/setup.sh)
DISKS="nas-data:30G nas-backup:100G nas-dokuman:50G nas-foto:150G"

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
lvs "$VG/$POOL" >/dev/null || { echo "thin pool $VG/$POOL not found"; exit 1; }

for d in $DISKS; do
  lv=${d%%:*} size=${d#*:}
  if lvs "$VG/$lv" >/dev/null 2>&1; then
    echo "$VG/$lv exists, left as it is"
  else
    # --setactivationskip n: activate on boot like Proxmox's own thin volumes.
    lvcreate --thin --virtualsize "$size" --name "$lv" --setactivationskip n "$VG/$POOL"
    echo "created /dev/$VG/$lv ($size thin, unformatted)"
  fi
done
lvs -o lv_name,lv_size,data_percent,pool_lv "$VG" | grep -E "LV|nas-"
