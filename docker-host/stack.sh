#!/bin/bash
# Shared deploy for the docker stack areas (proxy, auth, paperless, ...). Runs on the Proxmox host
# as the clone's owner, called by <area>/deploy.sh:
#   docker-host/stack.sh <area> <mode>      mode: status | deploy | force | rollback
# Ships master:<area> to the docker VM, swaps it into /opt/stacks/<area> (the old tree is kept for
# rollback) and runs `docker compose up -d` there. Live edits of the files in /opt/stacks/<area>
# stop a deploy. An optional <area>/hook.sh runs on the VM as root with:
#   check   before the swap in mode deploy: exit 1 when the running service was changed outside
#           the repo (UI edits); the deploy then stops
#   pre     before compose up (write config the containers read at start)
#   post <mode>  after compose up (apply config through the service's API)
#   status  print the service's own drift
# Secrets never come from git: compose files read /opt/secrets/<area>.env.
set -euo pipefail
AREA=${1:?usage: stack.sh <area> <mode>}
MODE=${2:-status}
CONFIGS_GIT=${CONFIGS_GIT:-/home/claude/work/ha-configs/.git}
VM=${DOCKER_VM:-sercan@192.168.0.222}
LIVE=/opt/stacks/$AREA
S=/var/lib/ha-configs/stacks/$AREA
G=(git --git-dir="$CONFIGS_GIT")

if [ "$(id -u)" -eq 0 ]; then
  echo "run as the clone's owner ($(stat -c %U "$CONFIGS_GIT")), not root: it uses that user's ssh keys"
  exit 1
fi
"${G[@]}" fetch -q origin master
NEW=$("${G[@]}" rev-parse --short origin/master)
"${G[@]}" cat-file -e "origin/master:$AREA/compose.yaml" 2>/dev/null \
  || { echo "$AREA/compose.yaml is not on master"; exit 1; }

vm() { ssh -o BatchMode=yes "$VM" "$@"; }

# Unpacks master:<area> into $S/stage (the area's files at its top).
ship() {
  "${G[@]}" archive "origin/master:$AREA" \
    | vm "sudo sh -c 'rm -rf $S/stage && mkdir -p $S/stage && tar -x -C $S/stage'"
}

# Prints files in $LIVE that differ from the deployed tree ($S/current); returns 0 when none do.
live_edits() {
  vm "sudo sh -c '[ -d $S/current ] || { echo \"not deployed by deploy.sh yet\"; exit 0; }
    diff -r -x .deployed $S/current $LIVE'"
}

hook() {  # hook <tree dir on the VM> <args...>
  local dir=$1; shift
  vm "sudo sh -c 'if [ -x $dir/hook.sh ]; then cd $dir && ./hook.sh $*; fi'"
}

compose_up() {
  vm "sudo docker compose --project-directory $LIVE -f $LIVE/compose.yaml up -d --remove-orphans"
}

case "$MODE" in
  status)
    echo "== $AREA -> $VM:$LIVE: deployed $(vm "cat $LIVE/.deployed 2>/dev/null || echo none"), master $NEW"
    live_edits | sed 's/^/   /' || true
    vm "sudo docker compose --project-directory $LIVE -f $LIVE/compose.yaml ps 2>/dev/null" | sed 's/^/   /' || true
    hook "$LIVE" status | sed 's/^/   /' || true
    ;;
  deploy|force)
    if [ "$MODE" = deploy ] && ! live_edits; then
      echo "Stopped: live edits above. Merge them into the repo or use force (Sercan only)."
      exit 1
    fi
    ship
    if [ "$MODE" = deploy ] && ! hook "$S/stage" check; then
      echo "Stopped: the running service differs from what was last applied (UI edits above)."
      echo "Merge them into the repo or use force (Sercan only)."
      exit 1
    fi
    vm "sudo sh -c 'set -e
      rm -rf $S/prev; mkdir -p /opt/stacks
      if [ -d $LIVE ]; then mv $LIVE $S/prev; fi
      cp -a $S/stage $LIVE && echo $NEW > $LIVE/.deployed
      rm -rf $S/current && mv $S/stage $S/current'"
    hook "$LIVE" pre
    compose_up
    hook "$LIVE" post "$MODE"
    echo "deployed $AREA $NEW -> $VM:$LIVE (previous tree kept for rollback)"
    ;;
  rollback)
    vm "sudo test -d $S/prev" || { echo "no previous version"; exit 1; }
    vm "sudo sh -c 'set -e
      rm -rf $S/stage && mv $LIVE $S/stage && mv $S/prev $LIVE && mv $S/stage $S/prev
      rm -rf $S/current && cp -a $LIVE $S/current && rm -f $S/current/.deployed'"
    hook "$LIVE" pre
    compose_up
    hook "$LIVE" post force
    echo "rolled back $AREA to $(vm "cat $LIVE/.deployed 2>/dev/null || echo none") (run rollback again to undo)"
    ;;
  *)
    echo "unknown mode $MODE (status | deploy | force | rollback)"
    exit 1
    ;;
esac
