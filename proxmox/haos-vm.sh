#!/bin/bash
# Builds VM 100 "haos" from the official Home Assistant OS qcow2 image; see README.md here.
# Fixed MAC so the router's DHCP reservation gives it 192.168.0.221. Run after docker-vm.sh: the
# HA backups to restore live on the NAS (docker VM). Asks before destroying an existing VM.
# Usage (root on the Proxmox host, from a checkout of this repo):
#   [HAOS_VERSION=16.3] [ZIGBEE_USB=10c4:ea60] [NO_START=1] proxmox/haos-vm.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=proxmox/lib.sh
. "$HERE/lib.sh"

VMID=${VMID:-100}
NAME=${NAME:-haos}
MAC=${MAC:-02:00:C0:A8:00:DD}
DISK_SIZE=32G
# SONOFF dongle vid:pid: ZBDongle-P 10c4:ea60, ZBDongle-E 1a86:55d4. Empty: no USB passthrough.
ZIGBEE_USB=${ZIGBEE_USB:-}
API=https://api.github.com/repos/home-assistant/operating-system/releases

need_root
if [ -n "$ZIGBEE_USB" ]; then
  [[ $ZIGBEE_USB =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]] || die "ZIGBEE_USB must be vid:pid"
  lsusb -d "$ZIGBEE_USB" >/dev/null || echo "warning: $ZIGBEE_USB not plugged in now (attached anyway)"
fi

# Release: HAOS_VERSION, or the newest stable release that ships the x86 OVA qcow2 (some point
# releases only ship board images); sha256 from the GitHub asset digest.
read -r HAOS_VERSION ASSET_URL SHA256 < <(curl -fsSL "$API?per_page=30" | python3 -I -c '
import json, sys
want = sys.argv[1]
for r in json.load(sys.stdin):
    if r["draft"] or r["prerelease"] or (want and r["tag_name"] != want):
        continue
    name = "haos_ova-%s.qcow2.xz" % r["tag_name"]
    for a in r["assets"]:
        if a["name"] == name:
            print(r["tag_name"], a["browser_download_url"], (a.get("digest") or "sha256:").split(":", 1)[1] or "-")
            sys.exit(0)' "${HAOS_VERSION:-}") || true
[ -n "${ASSET_URL:-}" ] || die "could not read the HAOS release from GitHub"
IMAGE=haos_ova-$HAOS_VERSION.qcow2
mkdir -p "$CACHE"
if [ ! -f "$CACHE/$IMAGE" ]; then
  echo "downloading HAOS $HAOS_VERSION"
  curl -fL --progress-bar "$ASSET_URL" -o "$CACHE/$IMAGE.xz.part"
  if [ "$SHA256" != - ]; then
    echo "$SHA256  $CACHE/$IMAGE.xz.part" | sha256sum -c --status || die "checksum mismatch"
  else
    echo "warning: no digest published for this asset, checksum not verified"
  fi
  xz -dc "$CACHE/$IMAGE.xz.part" > "$CACHE/$IMAGE.part"
  mv "$CACHE/$IMAGE.part" "$CACHE/$IMAGE" && rm -f "$CACHE/$IMAGE.xz.part"
fi

free_vmid "$VMID" "$NAME"

qm create "$VMID" \
  --name "$NAME" --tags haos --ostype l26 --machine q35 --bios ovmf \
  --efidisk0 "$STORAGE:0,efitype=4m,pre-enrolled-keys=0" \
  --cpu host --cores 4 --cpuunits 2048 \
  --memory 8192 --balloon 4096 --shares 2000 \
  --net0 "virtio=$MAC,bridge=$BRIDGE" \
  --scsihw virtio-scsi-single \
  --scsi0 "$STORAGE:0,import-from=$CACHE/$IMAGE,discard=on,ssd=1,iothread=1" \
  --boot order=scsi0 \
  --agent enabled=1 \
  --onboot 1 --startup order=2,up=30 \
  --description "Built by ha-configs proxmox/haos-vm.sh (HAOS $HAOS_VERSION)."
qm disk resize "$VMID" scsi0 "$DISK_SIZE"
[ -z "$ZIGBEE_USB" ] || qm set "$VMID" --usb0 "host=$ZIGBEE_USB"

echo "VM $VMID ($NAME) created: HAOS $HAOS_VERSION, MAC $MAC${ZIGBEE_USB:+, USB $ZIGBEE_USB}"
if [ "${NO_START:-0}" != 1 ]; then
  qm start "$VMID"
  echo "started; onboarding at http://<dhcp address>:8123 (192.168.0.221 once the reservation is on $MAC)"
fi
echo "next: restore the latest HA backup from the NAS (onboarding 'Restore from backup')"
