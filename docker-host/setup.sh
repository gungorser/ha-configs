#!/bin/bash
# Converges the docker VM (Debian 13) to this area: packages, Docker Engine from Docker's apt repo,
# managed files under files/, the /opt/stacks and /opt/secrets layout, and the four NAS disks
# mounted at /srv/data and /srv/nas/{backup,dokuman,foto}. Idempotent. Runs as root on the VM
# from an unpacked copy of the area (deploy.sh ships it); never from the repo checkout on the host.
# Usage: setup.sh check | apply
#   check: prints what apply would change; exit 0 when nothing.
#   apply: makes the changes. A NAS disk without a filesystem is only formatted when its label is
#          listed in FORMAT_NAS (first install, Sercan's approval); a disk that has any
#          filesystem, partition table or signature is never formatted.
set -euo pipefail
MODE=${1:-check}
HERE=$(cd "$(dirname "$0")" && pwd)
DOCKER_KEY_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
PACKAGES=(ca-certificates curl gnupg qemu-guest-agent unattended-upgrades nftables
  # Blender under Xvfb (software OpenGL via Mesa)
  xvfb xauth xz-utils libxi6 libxxf86vm1 libxfixes3 libxrender1 libgl1 libegl1 libgl1-mesa-dri
  libxkbcommon0 libxkbcommon-x11-0 libsm6 libice6)
# Blender (official tarball) and the "MCP for Blender" add-on 1.7 (ahujasid/blender-mcp addon.py),
# both pinned with their sha256.
BLENDER_VERSION=5.2.4
BLENDER_SHA256=2fd14c50987426897ba60237ee996edf2b4151f4b1a72a460ca20be58c1d2d86
BLENDER_URL=https://download.blender.org/release/Blender5.2/blender-$BLENDER_VERSION-linux-x64.tar.xz
ADDON_COMMIT=41a184322db3ccdcb2fdbc1f6994afe71bf9163c
ADDON_SHA256=d224965b72ecc2dc646156b85060bfc7befd08a959ff638e149e81e59c8cd701
ADDON_URL=https://raw.githubusercontent.com/ahujasid/blender-mcp/$ADDON_COMMIT/addon.py
ADDON_DIR=/var/lib/blender/.config/blender/${BLENDER_VERSION%.*}/scripts/addons
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
  mode=644; [ -x "$src" ] && mode=755   # executables (usr/local/sbin) keep their x bit
  if { ! cmp -s "$src" "$dst" || [ "$(stat -c %a "$dst")" != "$mode" ]; } && change "write $dst"; then
    install -D -m "$mode" "$src" "$dst"
    CHANGED_FILES+=("$dst")
    case "$dst" in /etc/systemd/*) systemctl daemon-reload ;; esac   # new units visible below
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
dir /srv/nas 755

# --- NAS disks (scsiN -> label -> mount point) -----------------------------------------------
# Same order as proxmox/nas-disks.sh and docker-vm.sh. A disk is found by its stable scsi id, must
# carry its own label once formatted (a disk with another label or filesystem is left alone), and
# is mounted by UUID.
NAS_DISKS="1:nas-data:/srv/data 2:nas-backup:/srv/nas/backup 3:nas-dokuman:/srv/nas/dokuman 4:nas-foto:/srv/nas/foto"
for d in $NAS_DISKS; do
  IFS=: read -r n label mnt <<< "$d"
  byid=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi$n
  [ -b "$byid" ] || { echo "$label: $byid not attached (proxmox/docker-vm.sh scsi$n)"; exit 1; }
  dev=$(readlink -f "$byid")
  dir "$mnt" 755
  if [ -z "$(wipefs --noheadings "$dev")" ] && ! blkid -p "$dev" >/dev/null 2>&1; then
    if [[ " ${FORMAT_NAS:-} " != *" $label "* ]]; then
      echo "$label: $dev ($byid) is empty; format it with FORMAT_NAS=\"$label\" (first install only)"
      DRIFT=1
      [ "$MODE" = check ] && continue
      exit 1
    elif change "format $dev as ext4 (label $label)"; then
      mkfs.ext4 -q -L "$label" -m 1 -E lazy_itable_init=1,discard "$dev"
    else
      continue
    fi
  fi
  if [ "$(blkid -s TYPE -o value "$dev")" != ext4 ] || [ "$(blkid -s LABEL -o value "$dev")" != "$label" ]; then
    echo "$label: $dev is not ext4 labelled $label, left alone"
    exit 1
  fi
  uuid=$(blkid -s UUID -o value "$dev")
  line="UUID=$uuid $mnt ext4 defaults,discard 0 2"
  if ! grep -qxF "$line" /etc/fstab && change "fstab: $line"; then
    sed -i "\| $mnt |d" /etc/fstab
    echo "$line" >> /etc/fstab
    systemctl daemon-reload
  fi
  if ! mountpoint -q "$mnt" && change "mount $mnt"; then
    mount "$mnt"
  fi
done

# --- Blender + MCP add-on (started on demand by blender-mcp-start, never at boot) -------------
if ! id blender >/dev/null 2>&1 && change "create system user blender (/var/lib/blender)"; then
  useradd --system --home-dir /var/lib/blender --create-home --shell /usr/sbin/nologin blender
fi
if [ ! -x "/opt/blender-$BLENDER_VERSION/blender" ] && change "install Blender $BLENDER_VERSION into /opt/blender-$BLENDER_VERSION"; then
  tmp=$(mktemp -d)
  curl -fsSL "$BLENDER_URL" -o "$tmp/blender.tar.xz"
  echo "$BLENDER_SHA256  $tmp/blender.tar.xz" | sha256sum -c --status || { rm -rf "$tmp"; echo "Blender checksum mismatch"; exit 1; }
  mkdir -p "$tmp/x" && tar -xJf "$tmp/blender.tar.xz" -C "$tmp/x" --strip-components=1
  mv "$tmp/x" "/opt/blender-$BLENDER_VERSION" && rm -rf "$tmp"
fi
if [ "$(readlink /opt/blender 2>/dev/null)" != "/opt/blender-$BLENDER_VERSION" ] && change "link /opt/blender -> /opt/blender-$BLENDER_VERSION"; then
  ln -sfn "/opt/blender-$BLENDER_VERSION" /opt/blender
fi
if ! echo "$ADDON_SHA256  $ADDON_DIR/blender_mcp.py" | sha256sum -c --status 2>/dev/null \
   && change "install the MCP add-on ${ADDON_COMMIT:0:12} into $ADDON_DIR"; then
  install -d -o blender -g blender "$ADDON_DIR"
  curl -fsSL "$ADDON_URL" -o "$ADDON_DIR/blender_mcp.py.new"
  echo "$ADDON_SHA256  $ADDON_DIR/blender_mcp.py.new" | sha256sum -c --status || { rm -f "$ADDON_DIR/blender_mcp.py.new"; echo "add-on checksum mismatch"; exit 1; }
  chown blender:blender "$ADDON_DIR/blender_mcp.py.new" && mv "$ADDON_DIR/blender_mcp.py.new" "$ADDON_DIR/blender_mcp.py"
  chown -R blender:blender /var/lib/blender/.config
fi

# --- services --------------------------------------------------------------------------------
for unit in qemu-guest-agent.service fstrim.timer docker.service unattended-upgrades.service blender-mcp-firewall.service; do
  systemctl cat "$unit" >/dev/null 2>&1 || continue
  if { ! systemctl is-enabled -q "$unit" || ! systemctl is-active -q "$unit"; } \
     && change "enable and start $unit"; then
    systemctl enable --now "$unit"
  fi
done
# Changed files take effect (systemd was reloaded when units were written).
RESTART_DOCKER=0
for f in "${CHANGED_FILES[@]}"; do
  case "$f" in
    /etc/systemd/system/docker.service.d/*|/etc/docker/*) RESTART_DOCKER=1 ;;
    /etc/nftables-blender-mcp.nft)
      echo "doing: reload blender-mcp-firewall ($f changed)"; systemctl restart blender-mcp-firewall ;;
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
