#!/bin/bash
# Stack hook for the proxy area (see docker-host/stack.sh), run on the docker VM as root from the
# area's folder: check | pre | post <mode> | status.
set -euo pipefail
cd "$(dirname "$0")"

npm_running() { [ "$(docker inspect -f '{{.State.Running}}' proxy-npm-1 2>/dev/null)" = true ]; }

secrets_ok() {
  local f rc=0
  for f in /opt/secrets/proxy.env /opt/secrets/duckdns.env; do
    if [ ! -s "$f" ]; then
      echo "missing $f (see proxy/README.md, Secrets)"; rc=1
    elif [ "$(stat -c '%a %U' "$f")" != "600 root" ]; then
      echo "$f must be mode 600, owner root"; rc=1
    fi
  done
  return $rc
}

case "${1:-status}" in
  check)
    # Nothing to compare before the first deploy or while NPM is down.
    if ! npm_running || [ ! -f /srv/data/proxy/ha-configs-applied.json ]; then exit 0; fi
    python3 npm_apply.py check
    ;;
  pre)
    secrets_ok
    install -d -m 755 /srv/data/proxy /srv/data/proxy/data /srv/data/proxy/letsencrypt
    ;;
  post)
    if [ "${2:-deploy}" = deploy ]; then python3 npm_apply.py deploy; else python3 npm_apply.py force; fi
    ;;
  status)
    if ! secrets_ok; then exit 0; fi
    if npm_running; then python3 npm_apply.py status; else echo "npm not running"; fi
    ;;
  *)
    echo "usage: hook.sh check | pre | post <mode> | status"; exit 1
    ;;
esac
