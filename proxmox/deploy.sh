#!/bin/bash
# Deploys the Proxmox host files in proxmox/host/ from origin/master to their live paths.
# Runs as root on the Proxmox host, from a clone of this repo (CONFIGS_GIT, default below).
# host/interfaces is reference only: status shows its diff, deploy never writes it (a bad network
# file locks the host out; change it by hand, then commit it here).
# mode: status | deploy (stops on live edits) | force (Sercan only) | rollback
set -u
MODE=${1:-status}
CONFIGS_GIT=${CONFIGS_GIT:-/home/claude/work/ha-configs/.git}
G="git -c safe.directory=* --git-dir=$CONFIGS_GIT"
STATE=/var/lib/ha-configs/proxmox
MARK=$STATE/.deployed
PREV=$STATE/prev

# repo file (under proxmox/host/) -> live path
FILES="storage.cfg:/etc/pve/storage.cfg
claude-remote-control.service:/etc/systemd/system/claude-remote-control.service
claude-work-mcp.json:/home/claude/work/.mcp.json
claude-work-settings.json:/home/claude/work/.claude/settings.json
wireguard/peers.conf:/etc/wireguard/peers.conf
wireguard/nftables-wg.nft:/etc/wireguard/nftables-wg.nft
wireguard/dnsmasq-vpn.conf:/etc/wireguard/dnsmasq-vpn.conf
wireguard/pve-wg-firewall.service:/etc/systemd/system/pve-wg-firewall.service
wireguard/vpn-dns.service:/etc/systemd/system/vpn-dns.service
wireguard/99-wireguard.conf:/etc/sysctl.d/99-wireguard.conf
wireguard/pve-vpn:/usr/local/sbin/pve-vpn
wireguard/vpn-qr:/usr/local/sbin/vpn-qr
pve-realm:/usr/local/sbin/pve-realm
glances/glances-api.service:/etc/systemd/system/glances-api.service
glances/drivetemp.conf:/etc/modules-load.d/drivetemp.conf"
# Host packages the VPN needs (the host stays minimal otherwise).
VPN_PACKAGES="wireguard-tools qrencode dnsmasq-base"
# Glances REST API for Home Assistant (no recommends: the full set pulls in ~150 packages).
GLANCES_PACKAGES="glances python3-uvicorn python3-jinja2 lm-sensors"
# uv/uvx for the claude user (runs the blender MCP server of .mcp.json), pinned with its sha256.
UV_VERSION=0.13.4
UV_SHA256=2b428396f12572d4429cf210ca234dd599a33b3af0958a4d5ed569d63e3f344f
REFERENCE="interfaces:/etc/network/interfaces"

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
# Fetch as the clone's owner: the deploy key and its ssh host alias live in that user's ~/.ssh.
OWNER=$(stat -c %U "$CONFIGS_GIT")
sudo -u "$OWNER" git --git-dir="$CONFIGS_GIT" fetch -q origin master || exit 1
NEW=$($G rev-parse --short origin/master) || exit 1

# Prints the files whose live copy differs from the deployed commit; returns 0 when none do.
live_edits() {
  [ -f "$MARK" ] || { echo "not deployed by deploy.sh yet"; return 1; }
  local old rc=0 src dst
  old=$(cat "$MARK")
  while IFS=: read -r src dst; do
    $G cat-file -e "$old:proxmox/host/$src" 2>/dev/null || continue   # new in a later commit
    $G show "$old:proxmox/host/$src" | diff - "$dst" >/dev/null 2>&1 || { echo "live edit: $dst"; rc=1; }
  done <<< "$FILES"
  return $rc
}

# Installs uv/uvx into ~claude/.local/bin when the pinned version is missing.
install_uv() {
  local bin=/home/claude/.local/bin tmp
  # `uv --version` prints "uv 0.13.4 (x86_64-unknown-linux-gnu)": compare the second word only.
  [ "$("$bin/uv" --version 2>/dev/null | cut -d' ' -f2)" = "$UV_VERSION" ] && return 0
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" -o "$tmp/uv.tgz" &&
    echo "$UV_SHA256  $tmp/uv.tgz" | sha256sum -c --status &&
    tar -xzf "$tmp/uv.tgz" -C "$tmp" --strip-components=1 &&
    install -d -o claude -g claude "$bin" &&
    install -m 755 -o claude -g claude "$tmp/uv" "$tmp/uvx" "$bin/" &&
    echo "installed uv $UV_VERSION into $bin" || echo "uv install FAILED (checksum or download)"
  rm -rf "$tmp"
}

# WireGuard VPN (wg0, UDP 51820): packages, routing, keys/config, units.
vpn() {
  local missing p
  missing=$(for p in $VPN_PACKAGES; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || echo "$p"; done)
  if [ -n "$missing" ]; then
    # shellcheck disable=SC2086  # word splitting of the package list is intended
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q $missing >/dev/null && echo "installed $missing"
  fi
  chmod 755 /usr/local/sbin/pve-vpn /usr/local/sbin/vpn-qr
  chmod 700 /etc/wireguard
  sysctl -q -p /etc/sysctl.d/99-wireguard.conf
  /usr/local/sbin/pve-vpn render
  systemctl daemon-reload
  systemctl enable -q --now pve-wg-firewall.service wg-quick@wg0.service vpn-dns.service
  systemctl restart pve-wg-firewall.service vpn-dns.service
}

glances_api() {
  missing=$(for p in $GLANCES_PACKAGES; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || echo "$p"; done)
  [ -z "$missing" ] || DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $missing >/dev/null || return 1
  modprobe drivetemp 2>/dev/null
  # Debian's own glances.service (XML-RPC server as root) is not used.
  systemctl disable --now glances.service >/dev/null 2>&1
  systemctl daemon-reload
  systemctl enable glances-api.service >/dev/null 2>&1
  systemctl restart glances-api.service && echo "glances: REST API on :61208 (HA VM only)"
}

after() {
  install_uv
  [ -f /etc/wireguard/peers.conf ] && vpn
  chmod 755 /usr/local/sbin/pve-realm && /usr/local/sbin/pve-realm
  glances_api
  systemctl daemon-reload
  # The unit is not restarted here: it runs the Claude session doing this deploy.
  systemctl enable claude-remote-control.service >/dev/null 2>&1
  echo "systemd reloaded (restart claude-remote-control by hand or at reboot to apply a unit change)"
}

case "$MODE" in
  status)
    echo "== proxmox -> host: deployed $(cat "$MARK" 2>/dev/null || echo none), master $NEW"
    live_edits | sed 's/^/   /'
    while IFS=: read -r src dst; do
      $G show "origin/master:proxmox/host/$src" | diff -u --label "repo:$src" - "$dst" \
        || echo "   (reference file $dst differs from the repo; update it in the repo)"
    done <<< "$REFERENCE"
    ;;
  deploy|force)
    if [ "$MODE" = deploy ] && [ -f "$MARK" ] && ! live_edits; then
      echo "Stopped: live edits above. Merge them into the repo or use force (Sercan only)."
      exit 1
    fi
    rm -rf "$PREV" && mkdir -p "$PREV" || exit 1
    while IFS=: read -r src dst; do
      # Sources may sit in subfolders (wireguard/...): create the matching folder under prev/.
      [ -f "$dst" ] && mkdir -p "$(dirname "$PREV/$src")" && cp -p "$dst" "$PREV/$src"
      # A new folder under /home/claude belongs to claude (Claude Code writes next to its files).
      if [ ! -d "$(dirname "$dst")" ]; then
        case "$dst" in /home/claude/*) install -d -o claude -g claude "$(dirname "$dst")" ;; *) mkdir -p "$(dirname "$dst")" ;; esac
      fi
      if $G show "origin/master:proxmox/host/$src" | diff -q - "$dst" >/dev/null 2>&1; then
        echo "unchanged $dst"
      else
        # /etc/pve is a FUSE filesystem: write in place (no rename), it is atomic per file there.
        $G show "origin/master:proxmox/host/$src" > "$STATE/.new" && cat "$STATE/.new" > "$dst" || exit 1
        echo "wrote $dst"
      fi
    done <<< "$FILES"
    rm -f "$STATE/.new"
    [ -f "$MARK" ] && cp -p "$MARK" "$PREV/.deployed"
    echo "$NEW" > "$MARK"
    after
    echo "deployed proxmox $NEW (previous files kept for rollback)"
    ;;
  rollback)
    [ -d "$PREV" ] || { echo "no previous version"; exit 1; }
    while IFS=: read -r src dst; do
      [ -f "$PREV/$src" ] && cat "$PREV/$src" > "$dst" && echo "restored $dst"
    done <<< "$FILES"
    if [ -f "$PREV/.deployed" ]; then cp -p "$PREV/.deployed" "$MARK"; else rm -f "$MARK"; fi
    after
    ;;
  *)
    echo "unknown mode $MODE (status | deploy | force | rollback)"
    exit 1
    ;;
esac
