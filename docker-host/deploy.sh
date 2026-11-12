#!/bin/bash
# Deploys the docker-host area from origin/master to the docker VM (VM 110) over SSH.
# Runs on the Proxmox host as the clone's owner (claude), from a clone of this repo: ships
# master:docker-host to the VM and runs setup.sh there as root (via sudo).
# State on the VM in /var/lib/ha-configs/docker-host: current/ (deployed tree), prev/ (the one
# before), stage/ (being deployed), .deployed (commit).
# mode: status | deploy (stops on live edits) | force (Sercan only) | rollback
# FORMAT_NAS="<labels>" lets setup.sh format those NAS disks when empty (first install only).
set -euo pipefail
MODE=${1:-status}
CONFIGS_GIT=${CONFIGS_GIT:-/home/claude/work/ha-configs/.git}
VM=${DOCKER_VM:-sercan@192.168.0.222}
S=/var/lib/ha-configs/docker-host
G=(git --git-dir="$CONFIGS_GIT")

if [ "$(id -u)" -eq 0 ]; then
  echo "run as the clone's owner ($(stat -c %U "$CONFIGS_GIT")), not root: it uses that user's ssh keys"
  exit 1
fi
"${G[@]}" fetch -q origin master
NEW=$("${G[@]}" rev-parse --short origin/master)

vm() { ssh -o BatchMode=yes "$VM" "$@"; }

ship() {
  "${G[@]}" archive origin/master docker-host \
    | vm "sudo sh -c 'rm -rf $S/stage && mkdir -p $S/stage && tar -x -C $S/stage'"
}

# Prints managed files that differ from the deployed tree; returns 0 when none do.
live_edits() {
  vm "sudo bash -s" <<EOF
set -u
[ -d $S/current/docker-host/files ] || { echo "not deployed by deploy.sh yet"; exit 0; }
rc=0
cd $S/current/docker-host/files
while IFS= read -r -d '' f; do
  cmp -s "\$f" "/\${f#./}" || { echo "live edit: /\${f#./}"; diff -u "\$f" "/\${f#./}" || true; rc=1; }
done < <(find . -type f -print0)
exit \$rc
EOF
}

run_setup() {  # run_setup <tree> <check|apply>
  vm "sudo env FORMAT_NAS='${FORMAT_NAS:-}' $S/$1/docker-host/setup.sh $2"
}

case "$MODE" in
  status)
    echo "== docker-host -> $VM: deployed $(vm "cat $S/.deployed 2>/dev/null || echo none"), master $NEW"
    live_edits | sed 's/^/   /' || true
    ship
    run_setup stage check | sed 's/^/   /' || true
    ;;
  deploy|force)
    if [ "$MODE" = deploy ] && ! live_edits; then
      echo "Stopped: live edits above. Merge them into the repo or use force (Sercan only)."
      exit 1
    fi
    ship
    run_setup stage apply
    vm "sudo sh -c 'rm -rf $S/prev; [ -d $S/current ] && mv $S/current $S/prev;
      [ -f $S/.deployed ] && mv $S/.deployed $S/prev/.deployed 2>/dev/null;
      mv $S/stage $S/current && echo $NEW > $S/.deployed'"
    echo "deployed docker-host $NEW -> $VM (previous tree kept for rollback)"
    ;;
  rollback)
    vm "sudo test -d $S/prev" || { echo "no previous version"; exit 1; }
    run_setup prev apply
    vm "sudo sh -c 'rm -rf $S/stage; [ -f $S/.deployed ] && mv $S/.deployed $S/current/.deployed;
      mv $S/current $S/stage && mv $S/prev $S/current && mv $S/stage $S/prev;
      if [ -f $S/current/.deployed ]; then mv $S/current/.deployed $S/.deployed; fi'"
    echo "rolled back docker-host (packages are not removed; run rollback again to undo)"
    ;;
  *)
    echo "unknown mode $MODE (status | deploy | force | rollback)"
    exit 1
    ;;
esac
