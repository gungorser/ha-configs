#!/bin/sh
# area-target: ha  (configs_status / configs_deploy on HA run only areas with this line)
# Deploys the 3D floor page (ha-floorplan: page + renders) to /config/www/gungors_floor. The files
# are not in this repository: ha-floorplan's deploy on the docker VM copies them to the NAS share `floorplan`
# (\\192.168.0.222\floorplan), which HA mounts as network storage `floorplan` (usage share,
# /share/floorplan). This script swaps a copy of that folder in; see README.md here.
# mode: status | deploy | force (same as deploy) | rollback
set -u
MODE=${1:-status}
CONFIG=${CONFIGS_ROOT:-/config}
# HA names the mount after the storage's name: accept `floorplan` or `Floorplan`.
SRC=${FLOORPLAN_SOURCE:-/share/floorplan}
if [ -z "${FLOORPLAN_SOURCE:-}" ] && [ ! -d "$SRC" ] && [ -d /share/Floorplan ]; then SRC=/share/Floorplan; fi
TARGET=$CONFIG/www/gungors_floor
STAGE=$CONFIG/.ha-configs-stage/floorplan
PREV=$CONFIG/.ha-configs-prev/floorplan

# The source's version: the stamp ha-floorplan's deploy writes, else the newest file time.
stamp() {
  if [ -f "$SRC/.version" ]; then cat "$SRC/.version"
  else echo "unstamped $(find "$SRC" -type f -exec stat -c %Y {} + 2>/dev/null | sort -n | tail -1)"; fi
}

case "$MODE" in
  status)
    OLD=$(cat "$TARGET/.deployed" 2>/dev/null || echo none)
    if [ -f "$SRC/index.html" ]; then NEW=$(stamp); else NEW="missing ($SRC not mounted or empty)"; fi
    echo "== floorplan $SRC -> $TARGET: deployed $OLD, source $NEW"
    ;;
  deploy|force)
    [ -f "$SRC/index.html" ] || { echo "$SRC/index.html missing: is network storage 'floorplan' mounted?"; exit 1; }
    NEW=$(stamp)
    rm -rf "$STAGE" && mkdir -p "$STAGE" "$CONFIG/.ha-configs-prev" || exit 1
    cp -R "$SRC/." "$STAGE/" || { rm -rf "$STAGE"; echo "copy failed, nothing changed"; exit 1; }
    rm -f "$STAGE/.version"
    echo "$NEW" > "$STAGE/.deployed"
    rm -rf "$PREV"
    if [ -e "$TARGET" ]; then mv "$TARGET" "$PREV" || exit 1; fi
    mkdir -p "$(dirname "$TARGET")"
    mv "$STAGE" "$TARGET" || { echo "swap failed, restoring"; mv "$PREV" "$TARGET"; exit 1; }
    echo "deployed floorplan $NEW -> $TARGET ($(du -sh "$TARGET" | cut -f1); previous kept for rollback)"
    ;;
  rollback)
    [ -e "$PREV" ] || { echo "no previous version of $TARGET"; exit 1; }
    rm -rf "$STAGE"
    if [ -e "$TARGET" ]; then mv "$TARGET" "$STAGE" || exit 1; fi
    mv "$PREV" "$TARGET" || exit 1
    if [ -e "$STAGE" ]; then mv "$STAGE" "$PREV"; fi
    echo "rolled back $TARGET (rollback again to undo)"
    ;;
  *)
    echo "unknown mode $MODE (status | deploy | force | rollback)"
    exit 1
    ;;
esac
