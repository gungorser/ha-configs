#!/bin/bash
# Converges the docker VM (Debian 13) to this area: packages, Docker Engine from Docker's apt repo,
# managed files under files/, the /opt/stacks, /opt/secrets and /srv/data layout, and the nas-data
# disk mounted at /srv/data. Idempotent. Runs as root on the VM from an unpacked copy of the area
# (deploy.sh ships it); never run from the repo checkout on the host.
# Usage: setup.sh check | apply
#   check: prints what apply would change; exit 0 when nothing.
#   apply: makes the changes. A nas-data disk without a filesystem is only formatted when
#          FORMAT_NAS_DATA=1 is set (first install, Sercan's approval); a disk that has any
#          filesystem, partition table or signature is never formatted.
set -euo pipefail
MODE=${1:-check}
HERE=$(cd "$(dirname "$0")" && pwd)
NAS_DEV=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
NAS_MNT=/srv/data
NAS_LABEL=nas-data
DOCKER_KEY_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
PACKAGES=(ca-certificates curl gnupg qemu-guest-agent unattended-upgrades)
DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
DRIFT=0

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
case "$MODE" in check|apply) ;; *) echo "usage: $0 check|apply"; exit 1 ;; esac

# change <description>: in check mode reports and returns 1 (skip the action); in apply mode
# reports and returns 0 (do it).
change() {
  DRIFT=1
  if [ "$MODE" = check ]; then echo "would: $*"; return 1; fi
  echo "doing: $*"
}

missing_packages() {
  local p
  for p in "$@"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || echo "$p"; done
}

# --- packages ------------------------------------------------------------------------------
mapfile -t MISSING < <(missing_packages "${PACKAGES[@]}")
if [ ${#MISSING[@]} -gt 0 ] && change "install ${MISSING[*]}"; then
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${MISSING[@]}"
fi

# --- Docker apt repo -------------------------------------------------------------------------
KEY=/etc/apt/keyrings/docker.asc
if [ ! -s "$KEY" ] && change "add Docker's apt key ($DOCKER_KEY_FPR)"; then
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o "$KEY.new"
  gpg --show-keys --with-colons "$KEY.new" | grep -q "^fpr:*$DOCKER_KEY_FPR:" \
    || { rm -f "$KEY.new"; echo "Docker key fingerprint mismatch"; exit 1; }
  chmod 644 "$KEY.new" && mv "$KEY.new" "$KEY"
fi

# --- managed files (files/<path> -> /<path>) -------------------------------------------------
CHANGED_FILES=()
while IFS= read -r -d '' src; do
  dst=/${src#"$HERE/files/"}
  if ! cmp -s "$src" "$dst" && change "write $dst"; then
    install -D -m 644 "$src" "$dst"
    CHANGED_FILES+=("$dst")
  fi
done < <(find "$HERE/files" -type f -print0 | sort -z)

mapfile -t MISSING < <(missing_packages "${DOCKER_PACKAGES[@]}")
if [ ${#MISSING[@]} -gt 0 ] && change "install ${MISSING[*]}"; then
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${MISSING[@]}"
fi

# --- directories -----------------------------------------------------------------------------
dir() {
  local path=$1 mode=$2
  if [ "$(stat -c '%a %U:%G' "$path" 2>/dev/null)" != "$mode root:root" ] \
     && change "directory $path ($mode root:root)"; then
    install -d -m "$mode" -o root -g root "$path"
  fi
}
dir /opt/stacks 755
dir /opt/secrets 700
dir "$NAS_MNT" 755

# --- nas-data disk -> /srv/data --------------------------------------------------------------
[ -b "$NAS_DEV" ] || { echo "nas-data disk $NAS_DEV not attached (proxmox/docker-vm.sh scsi1)"; exit 1; }
DEV=$(readlink -f "$NAS_DEV")
if [ -z "$(wipefs --noheadings "$DEV")" ] && ! blkid -p "$DEV" >/dev/null 2>&1; then
  if [ "${FORMAT_NAS_DATA:-0}" != 1 ]; then
    echo "nas-data $DEV ($NAS_DEV) is empty; format it with FORMAT_NAS_DATA=1 (first install only)"
    DRIFT=1
    [ "$MODE" = check ] || exit 1
  elif change "format $DEV as ext4 (label $NAS_LABEL)"; then
    mkfs.ext4 -q -L "$NAS_LABEL" -m 1 -E lazy_itable_init=1,discard "$DEV"
  fi
fi
UUID=$(blkid -s UUID -o value "$DEV" 2>/dev/null || true)
if [ -n "$UUID" ]; then
  [ "$(blkid -s TYPE -o value "$DEV")" = ext4 ] || { echo "$DEV is not ext4, left alone"; exit 1; }
  LINE="UUID=$UUID $NAS_MNT ext4 defaults,discard 0 2"
  if ! grep -qxF "$LINE" /etc/fstab && change "fstab: $LINE"; then
    sed -i "\| $NAS_MNT |d" /etc/fstab
    echo "$LINE" >> /etc/fstab
    systemctl daemon-reload
  fi
  if ! mountpoint -q "$NAS_MNT" && change "mount $NAS_MNT"; then
    mount "$NAS_MNT"
  fi
fi

# --- services --------------------------------------------------------------------------------
for unit in qemu-guest-agent.service fstrim.timer docker.service unattended-upgrades.service; do
  systemctl cat "$unit" >/dev/null 2>&1 || continue
  if { ! systemctl is-enabled -q "$unit" || ! systemctl is-active -q "$unit"; } \
     && change "enable and start $unit"; then
    systemctl enable --now "$unit"
  fi
done
# Changed files take effect: systemd units first, then the Docker daemon.
RESTART_DOCKER=0
for f in "${CHANGED_FILES[@]}"; do
  case "$f" in
    /etc/systemd/*) systemctl daemon-reload; RESTART_DOCKER=1 ;;
    /etc/docker/*) RESTART_DOCKER=1 ;;
  esac
done
if [ $RESTART_DOCKER = 1 ] && systemctl is-active -q docker; then
  echo "doing: restart docker (its config changed)"
  systemctl restart docker
fi

if [ "$MODE" = check ]; then
  [ $DRIFT -eq 0 ] && echo "docker-host: in sync"
  exit $DRIFT
fi
echo "docker-host: applied"
