#!/bin/sh
# Deploys esphome/*.yaml to /config/esphome (the ESPHome Device Builder folder). Not a swap: that
# folder also holds secrets.yaml, archive/ and the add-on's own .git, which are never touched.
# Only our device files are written; nothing is deleted. Installing on a device stays a click in
# the ESPHome UI. Run by shell_command.configs_deploy / configs_status; see README.md here.
# mode: status | deploy (stops on live edits) | force (Sercan only) | rollback
set -u
MODE=${1:-status}
G="git -c safe.directory=/config/.ha-configs.git --git-dir=/config/.ha-configs.git"
LIVE=/config/esphome
MARK=$LIVE/.ha-configs-deployed
PREV=/config/.ha-configs-prev/esphome
NEW=$($G rev-parse --short master) || exit 1
files() { $G ls-tree --name-only "$1:esphome" | grep '\.yaml$'; }

# Prints the device files that differ from the deployed commit; returns 0 when none do.
live_edits() {
  [ -f "$MARK" ] || { echo "$LIVE: not deployed by configs_deploy yet"; return 1; }
  OLD=$(cat "$MARK")
  RC=0
  for f in $(files "$OLD"); do
    $G show "$OLD:esphome/$f" | diff - "$LIVE/$f" >/dev/null 2>&1 || { echo "live edit: $f"; RC=1; }
  done
  return $RC
}

case "$MODE" in
  status)
    echo "== esphome -> $LIVE: deployed $(cat "$MARK" 2>/dev/null || echo none), master $NEW"
    live_edits | sed 's/^/   /'
    ;;
  deploy|force)
    if [ "$MODE" = deploy ] && ! live_edits; then
      echo "Nothing changed. Merge the live edits into the repo or use force."
      exit 1
    fi
    rm -rf "$PREV" && mkdir -p "$PREV" || exit 1
    for f in $(files master); do
      [ -f "$LIVE/$f" ] && cp -p "$LIVE/$f" "$PREV/$f"
      $G show "master:esphome/$f" > "$LIVE/.$f.new" && mv "$LIVE/.$f.new" "$LIVE/$f" || exit 1
      echo "wrote $f"
    done
    [ -f "$MARK" ] && cp -p "$MARK" "$PREV/.ha-configs-deployed"
    echo "$NEW" > "$MARK"
    echo "deployed esphome $NEW -> $LIVE (previous files kept for rollback)"
    ;;
  rollback)
    [ -d "$PREV" ] || { echo "no previous version"; exit 1; }
    for p in "$PREV"/*; do
      [ -f "$p" ] && cp -p "$p" "$LIVE/$(basename "$p")" && echo "restored $(basename "$p")"
    done
    if [ -f "$PREV/.ha-configs-deployed" ]; then cp -p "$PREV/.ha-configs-deployed" "$MARK"; else rm -f "$MARK"; fi
    ;;
  *)
    echo "unknown mode $MODE (status | deploy | force | rollback)"
    exit 1
    ;;
esac
