#!/bin/bash
# Builds VM 110 "docker" (Debian 13 cloud image) from scratch; see README.md here.
# The VM holds no data of its own: services live in the repo, data on the NAS LVs (nas-disks.sh),
# attached by their /dev path as scsi1..scsi4 (never formatted or deleted here). Asks before destroying an existing VM.
# Usage (root on the Proxmox host, from a checkout of this repo):
#   SSH_KEYS=<file with public keys> [SSD2=/dev/disk/by-id/...] [NO_START=1] proxmox/docker-vm.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=proxmox/lib.sh
. "$HERE/lib.sh"

VMID=${VMID:-110}
NAME=${NAME:-docker}
IP=${IP:-192.168.0.222/24}
GW=192.168.0.1
MAC=${MAC:-02:00:C0:A8:00:DE}
DISK_SIZE=32G
# scsi1..scsi4, in this order (docker-host/setup.sh finds them by scsi number)
NAS_DISKS=(nas-data nas-backup nas-dokuman nas-foto)
SSH_KEYS=${SSH_KEYS:-/home/claude/.ssh/vm-authorized_keys}
SSD2=${SSD2:-}
CIUSER=${CIUSER:-sercan}
VENDOR_SNIPPET=docker-vm-vendor.yaml
IMAGE_URL=https://cloud.debian.org/images/cloud/trixie/latest
IMAGE=debian-13-generic-amd64.qcow2

need_root
[ -s "$SSH_KEYS" ] || die "SSH_KEYS=$SSH_KEYS is missing or empty (public keys for $CIUSER)"
for lv in "${NAS_DISKS[@]}"; do
  [ -b "/dev/pve/$lv" ] || die "/dev/pve/$lv not found: run proxmox/nas-disks.sh first"
done
[ -z "$SSD2" ] || [ -b "$SSD2" ] || die "SSD2=$SSD2 is not a block device"
pvesm status --content snippets 2>/dev/null | grep -q '^local ' \
  || die "storage 'local' has no 'snippets' content: deploy proxmox/host/storage.cfg first"

# Image: download when missing or older than the published checksum, verify sha512.
mkdir -p "$CACHE"
curl -fsSL "$IMAGE_URL/SHA512SUMS" -o "$CACHE/$IMAGE.SHA512SUMS"
SUM=$(awk -v f="$IMAGE" '$2 == f {print $1}' "$CACHE/$IMAGE.SHA512SUMS")
[ -n "$SUM" ] || die "$IMAGE not in SHA512SUMS"
if ! echo "$SUM  $CACHE/$IMAGE" | sha512sum -c --status 2>/dev/null; then
  echo "downloading $IMAGE"
  curl -fL --progress-bar "$IMAGE_URL/$IMAGE" -o "$CACHE/$IMAGE.part"
  echo "$SUM  $CACHE/$IMAGE.part" | sha512sum -c --status || die "checksum mismatch for $IMAGE"
  mv "$CACHE/$IMAGE.part" "$CACHE/$IMAGE"
fi

free_vmid "$VMID" "$NAME"

# cloud-init vendor data: guest agent; the docker-host area does the rest.
install -m 644 "$HERE/cloud-init/$VENDOR_SNIPPET" "/var/lib/vz/snippets/$VENDOR_SNIPPET"

qm create "$VMID" \
  --name "$NAME" --tags docker --ostype l26 --machine q35 \
  --cpu host --cores 4 --cpuunits 1024 \
  --memory 12288 --balloon 6144 --shares 1000 \
  --net0 "virtio=$MAC,bridge=$BRIDGE" \
  --scsihw virtio-scsi-single \
  --scsi0 "$STORAGE:0,import-from=$CACHE/$IMAGE,discard=on,ssd=1,iothread=1" \
  --ide2 "$STORAGE:cloudinit" \
  --boot order=scsi0 \
  --serial0 socket --vga serial0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --onboot 1 --startup order=1 \
  --ciuser "$CIUSER" --sshkeys "$SSH_KEYS" \
  --ipconfig0 "ip=$IP,gw=$GW" --nameserver "$GW" \
  --cicustom "vendor=local:snippets/$VENDOR_SNIPPET" \
  --description "Built by ha-configs proxmox/docker-vm.sh. NAS disks on scsi1-4, see proxmox/README.md."
qm disk resize "$VMID" scsi0 "$DISK_SIZE"
n=1
for lv in "${NAS_DISKS[@]}"; do
  qm set "$VMID" "--scsi$n" "/dev/pve/$lv,discard=on,ssd=1,iothread=1,backup=0" >/dev/null
  n=$((n + 1))
done
[ -z "$SSD2" ] || qm set "$VMID" --scsi5 "$SSD2,discard=on,ssd=1,iothread=1,backup=0"

echo "VM $VMID ($NAME) created: ${IP%/*}, MAC $MAC, NAS disks on scsi1-4${SSD2:+, SSD2 on scsi5}"
if [ "${NO_START:-0}" != 1 ]; then
  qm start "$VMID"
  echo "started; first boot runs cloud-init (~1-2 min), then: ssh $CIUSER@${IP%/*}"
fi
echo "next: docker-host/deploy.sh deploy (packages, Docker, mounts the NAS disks)"
