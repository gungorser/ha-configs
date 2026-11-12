#!/bin/bash
# Builds VM 100 "haos" from the official Home Assistant OS qcow2 image; see README.md here.
# Fixed MAC so the router's DHCP reservation gives it 192.168.0.221. Run after docker-vm.sh: the
# HA backups to restore live on the NAS (docker VM). Asks before destroying an existing VM.
# The VM takes over the Pi's address: it is created stopped and without autostart, and is only
# started at the cutover, after the Pi is shut down (START=1 ONBOOT=1 then, or qm set/start).
# Usage (root on the Proxmox host, from a checkout of this repo):
#   [HAOS_VERSION=18.4] [ZIGBEE_USB=1a86:55d4] [BT_USB=8087:0026] [START=1] [ONBOOT=1] proxmox/haos-vm.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=proxmox/lib.sh
. "$HERE/lib.sh"

VMID=${VMID:-100}
NAME=${NAME:-haos}
MAC=${MAC:-02:00:C0:A8:00:DD}
DISK_SIZE=32G
# Zigbee: SONOFF Zigbee 3.0 USB Dongle Plus V2 (ZBDongle-E, ember; Z2M uses its /dev/serial/by-id
# name, which stays the same inside the VM). ZBDongle-P would be 10c4:ea60. Empty: no passthrough.
ZIGBEE_USB=${ZIGBEE_USB-1a86:55d4}
# Optional Bluetooth: the Beelink's Intel AX201 (8087:0026), for HA's Bluetooth integration.
BT_USB=${BT_USB:-}
START=${START:-0}
ONBOOT=${ONBOOT:-0}
# Pinned release and the sha256 of its haos_ova qcow2.xz (GitHub asset digest, checked 2026-11-12).
HAOS_PINNED=18.4
HAOS_PINNED_SHA256=756ec485b1b153099ca53e88a5eebd63a801d56b791afe5c6d63ef94a35dc02d
HAOS_VERSION=${HAOS_VERSION:-$HAOS_PINNED}
API=https://api.github.com/repos/home-assistant/operating-system/releases

need_root
for usb in $ZIGBEE_USB $BT_USB; do
  [[ $usb =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]] || die "USB ids must be vid:pid ($usb)"
  lsusb -d "$usb" >/dev/null || echo "warning: $usb not plugged in now (attached anyway)"
done

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
if [ "$HAOS_VERSION" = "$HAOS_PINNED" ]; then
  [ "$SHA256" = "$HAOS_PINNED_SHA256" ] || die "GitHub digest for $HAOS_VERSION differs from the pinned sha256"
fi
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
  --onboot "$ONBOOT" --startup order=2,up=30 \
  --description "Built by ha-configs proxmox/haos-vm.sh (HAOS $HAOS_VERSION)."
qm disk resize "$VMID" scsi0 "$DISK_SIZE"
[ -z "$ZIGBEE_USB" ] || qm set "$VMID" --usb0 "host=$ZIGBEE_USB,usb3=0" >/dev/null
[ -z "$BT_USB" ] || qm set "$VMID" --usb1 "host=$BT_USB" >/dev/null

echo "VM $VMID ($NAME) created: HAOS $HAOS_VERSION, MAC $MAC${ZIGBEE_USB:+, USB $ZIGBEE_USB}${BT_USB:+, BT $BT_USB}, onboot $ONBOOT"
if [ "$START" = 1 ]; then
  qm start "$VMID"
  echo "started; onboarding at http://<dhcp address>:8123 (192.168.0.221 once the reservation is on $MAC)"
else
  echo "not started (START=1 or qm start $VMID at the cutover, after the Pi is off)"
fi
echo "next: restore the latest HA backup from the NAS (onboarding 'Restore from backup')"
