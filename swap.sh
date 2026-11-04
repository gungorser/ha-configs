#!/bin/sh
# Shared "swap" deploy, used by the deploy.sh of areas whose live target is a folder that holds
# only our files (gungors/, pyscript/, blueprints/). Run on HA (busybox sh) from the bare clone:
#   git show master:swap.sh | sh -s -- <mode> <tree path> <live target>
# mode: status | deploy | force | rollback
# deploy: unpacks master:<tree path> into a hidden stage folder and swaps it with the target
# (mv on the same disk); the old target is kept in /config/.ha-configs-prev for rollback.
# deploy stops when the target differs from the commit it was deployed from (live edits);
# force deploys anyway (Sercan's approval only).
set -u
MODE=${1:-status}
SRC=$2
TARGET=$3
CONFIG=${CONFIGS_ROOT:-/config}
G="git -c safe.directory=$CONFIG/.ha-configs.git --git-dir=$CONFIG/.ha-configs.git"
KEY=$(echo "$SRC" | tr / _)
STAGE=$CONFIG/.ha-configs-stage/$KEY
PREV=$CONFIG/.ha-configs-prev/$KEY
NEW=$($G rev-parse --short master) || exit 1

# Prints the live edits (target vs the commit in its .deployed); returns 0 when there are none.
live_edits() {
  [ -f "$TARGET/.deployed" ] || { echo "$TARGET: not deployed by configs_deploy yet"; return 1; }
  OLD=$(cat "$TARGET/.deployed")
  CHECK=$STAGE.check
  rm -rf "$CHECK" && mkdir -p "$CHECK" || return 1
  $G archive "$OLD:$SRC" | tar -x -C "$CHECK" || { rm -rf "$CHECK"; return 1; }
  echo "$OLD" > "$CHECK/.deployed"
  diff -r "$CHECK" "$TARGET"
  RC=$?
  rm -rf "$CHECK"
  return $RC
}

case "$MODE" in
  status)
    OLD=$(cat "$TARGET/.deployed" 2>/dev/null || echo none)
    echo "== $SRC -> $TARGET: deployed $OLD, master $NEW"
    live_edits >/dev/null 2>&1 || echo "   live edits or not deployed yet (configs_deploy shows the diff)"
    ;;
  deploy|force)
    if [ "$MODE" = deploy ] && ! live_edits; then
      echo "$TARGET has live edits (above); nothing changed. Merge them into the repo or use force."
      exit 1
    fi
    rm -rf "$STAGE" && mkdir -p "$STAGE" "$CONFIG/.ha-configs-prev" || exit 1
    $G archive "master:$SRC" | tar -x -C "$STAGE" || { echo "unpack failed"; exit 1; }
    echo "$NEW" > "$STAGE/.deployed"
    rm -rf "$PREV"
    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then mv "$TARGET" "$PREV" || exit 1; fi
    mkdir -p "$(dirname "$TARGET")"
    mv "$STAGE" "$TARGET" || { echo "swap failed, restoring"; mv "$PREV" "$TARGET"; exit 1; }
    echo "deployed $SRC $NEW -> $TARGET (previous kept for rollback)"
    ;;
  rollback)
    [ -e "$PREV" ] || [ -L "$PREV" ] || { echo "no previous version of $TARGET"; exit 1; }
    rm -rf "$STAGE"
    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then mv "$TARGET" "$STAGE" || exit 1; fi
    mv "$PREV" "$TARGET" || exit 1
    if [ -e "$STAGE" ] || [ -L "$STAGE" ]; then mv "$STAGE" "$PREV"; fi
    echo "rolled back $TARGET (rollback again to undo)"
    ;;
  *)
    echo "unknown mode $MODE (status | deploy | force | rollback)"
    exit 1
    ;;
esac
