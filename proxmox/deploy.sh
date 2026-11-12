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
claude-remote-control.service:/etc/systemd/system/claude-remote-control.service"
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
    $G show "$old:proxmox/host/$src" | diff - "$dst" >/dev/null 2>&1 || { echo "live edit: $dst"; rc=1; }
  done <<< "$FILES"
  return $rc
}

after() {
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
      [ -f "$dst" ] && cp -p "$dst" "$PREV/$src"
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
