#!/bin/bash
# Stack hook for the immich area (see docker-host/stack.sh), run on the docker VM as root from the
# area's folder: check | pre | post <mode> | status.
#   pre:  generates /opt/secrets/immich.env once (DB password), writes the settings file
#         /opt/secrets/immich/immich.json = repo immich.json + the OIDC client secret from
#         /opt/secrets/oidc/immich.secret (made by the auth area), prepares the folders.
#   post: waits for Immich; on a fresh install creates the local break-glass admin
#         (password in /opt/secrets/immich/admin.password, never shown).
set -euo pipefail
cd "$(dirname "$0")"
ENV=/opt/secrets/immich.env
SEC=/opt/secrets/immich
OIDC_SECRET=/opt/secrets/oidc/immich.secret
DATA=/srv/data/immich
PHOTOS=/srv/nas/foto/immich
SERVER=immich-immich-server-1
ADMIN_EMAIL=admin@gungors.duckdns.org

rand() { openssl rand -hex "${1:-24}"; }   # hex: Postgres wants A-Za-z0-9 only

# api <method> <path> [json]: Immich API on the container's address (no published port).
api() {
  local ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$SERVER" | awk '{print $1}')
  curl -fsS -X "$1" -H 'Content-Type: application/json' ${3:+--data "$3"} "http://$ip:2283/api$2"
}

case "${1:-status}" in
  check)
    exit 0   # server settings are locked to immich.json; users and albums live in the database
    ;;
  pre)
    [ -s "$OIDC_SECRET" ] || { echo "missing $OIDC_SECRET: deploy the auth area first"; exit 1; }
    if [ ! -s "$ENV" ]; then
      pw=$(rand 24)
      (umask 077; printf 'DB_PASSWORD=%s\nPOSTGRES_PASSWORD=%s\n' "$pw" "$pw" > "$ENV")
      echo "generated $ENV"
    fi
    install -d -m 700 "$SEC"
    (umask 077; python3 - "$OIDC_SECRET" > "$SEC/immich.json.new" <<'PY'
import json, sys
cfg = json.load(open("immich.json"))
cfg["oauth"]["clientSecret"] = open(sys.argv[1]).read().strip()
print(json.dumps(cfg, indent=2, ensure_ascii=False))
PY
    )
    mv "$SEC/immich.json.new" "$SEC/immich.json"
    install -d -m 755 "$DATA"
    install -d -m 700 "$DATA/postgres" "$DATA/model-cache"
    # Root only: the Samba share `foto` (/srv/nas/foto) must not reach Immich's library.
    install -d -m 700 "$PHOTOS"
    ;;
  post)
    for _ in $(seq 120); do
      [ "$(docker inspect -f '{{.State.Health.Status}}' "$SERVER" 2>/dev/null)" = healthy ] && break
      sleep 2
    done
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$SERVER")" = healthy ] \
      || { echo "$SERVER not healthy"; docker logs --tail 40 "$SERVER" 2>&1 | sed 's/^/  /'; exit 1; }
    if api GET /server/config | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["isInitialized"] else 1)'; then
      echo "immich: initialized"
    else
      pw=$(rand 16)
      api POST /auth/admin-sign-up \
        "$(printf '{"email":"%s","password":"%s","name":"Admin"}' "$ADMIN_EMAIL" "$pw")" > /dev/null
      (umask 077; printf '%s\n' "$pw" > "$SEC/admin.password")
      echo "immich: created break-glass admin $ADMIN_EMAIL (password in $SEC/admin.password)"
    fi
    api GET /server/features | python3 -c 'import json,sys; f=json.load(sys.stdin); print("immich: oauth", f["oauth"], "password login", f["passwordLogin"])'
    ;;
  status)
    docker ps --filter name=immich- --format '{{.Names}}: {{.Status}}'
    ;;
  *)
    echo "usage: hook.sh check | pre | post <mode> | status"; exit 1
    ;;
esac
