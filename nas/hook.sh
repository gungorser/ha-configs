#!/bin/bash
# Stack hook for the nas area (see docker-host/stack.sh), run on the docker VM as root from the
# area's folder: check | pre | post <mode> | status.
#   pre:  writes /srv/data/nas/accounts: the groups from the deployed LLDAP lists (auth area, for
#         folder owners), as users only the service accounts (LLDAP group servis, ha-backup,
#         paperless; people have no NAS account), sets owners/modes of the shared folders,
#         installs set-password and set-smb-password, builds the image.
#   post: recreates the container when smb.conf or the accounts changed, waits for smbd, deletes
#         SMB passwords of accounts no longer listed, lists the accounts that have an SMB password.
set -euo pipefail
cd "$(dirname "$0")"
LL=/opt/stacks/auth/lldap-bootstrap
ACC=/srv/data/nas/accounts
ADMIN_GID=20000 AILE_GID=20001 HAB_UID=10100 PL_UID=8003

case "${1:-status}" in
  check)
    exit 0   # SMB passwords live in Samba's passdb, not in the repo
    ;;
  pre)
    [ -d "$LL" ] || { echo "missing $LL: deploy the auth area first"; exit 1; }
    install -d -m 700 /srv/data/nas /srv/data/nas/samba
    python3 - "$LL" > "$ACC.new" <<'PY'
import glob, json, sys
ll = sys.argv[1]
def objs(pattern):
    for f in sorted(glob.glob(f"{ll}/{pattern}")):
        for line in open(f):
            if line.strip():
                yield json.loads(line)
groups = {g["name"]: g["gidnumber"] for g in objs("group-configs/*.json") if "gidnumber" in g}
for name, gid in groups.items():
    print("group", name, gid)
print("group ha-backup 20100")
print("group paperless 8003")
for u in objs("user-configs/*.json"):
    if "uidnumber" not in u or "servis" not in u.get("groups", []):
        continue   # people log in through Authelia only; the NAS has service accounts
    extra = ",".join(g for g in u.get("groups", []) if g in groups)
    print("user", u["id"], u["uidnumber"], u["gidnumber"], extra)
print("user ha-backup 10100 20100")         # HA's network storage; SMB only, not in admin
print("user paperless 8003 8003")           # owner of the scan inbox (Paperless container uid)
PY
    chmod 644 "$ACC.new" && mv "$ACC.new" "$ACC"
    install -d -m 2770 -o root -g "$ADMIN_GID" /srv/nas/backup
    install -d -m 2770 -o "$HAB_UID" -g "$ADMIN_GID" /srv/nas/backup/ha
    install -d -m 2770 -o root -g "$AILE_GID" /srv/nas/dokuman/genel
    install -d -m 2771 -o root -g "$AILE_GID" /srv/nas/foto   # o+x: ha-media reaches muzik/, lists nothing
    install -d -m 2775 -o root -g "$AILE_GID" /srv/nas/foto/muzik
    install -d -m 2775 -o root -g "$ADMIN_GID" /srv/nas/foto/floorplan   # o+rx: ha-media reads it
    install -d -m 750 -o "$PL_UID" -g "$PL_UID" /srv/nas/dokuman/paperless/consume
    install -m 755 set-smb-password /usr/local/sbin/set-smb-password
    install -m 755 set-password /usr/local/sbin/set-password
    docker compose --project-directory . -f compose.yaml build -q
    ;;
  post)
    # smb.conf is a single-file bind mount (pinned to the old file after the swap) and the
    # accounts are created at container start: recreate the container when either changed.
    if ! docker exec nas-samba-1 cat /etc/samba/smb.conf 2>/dev/null | cmp -s - smb.conf \
       || ! docker exec nas-samba-1 cat /etc/nas/accounts 2>/dev/null | cmp -s - "$ACC"; then
      echo "nas: smb.conf or accounts changed, recreating the container"
      docker compose --project-directory . -f compose.yaml up -d --force-recreate
    fi
    for _ in $(seq 30); do
      [ "$(docker inspect -f '{{.State.Health.Status}}' nas-samba-1 2>/dev/null)" = healthy ] && break
      sleep 2
    done
    docker exec nas-samba-1 smbcontrol smbd ping >/dev/null && echo "nas: smbd running"
    # SMB passwords of accounts that are no longer listed (people, since 2026-11-27).
    for u in $(docker exec nas-samba-1 pdbedit -L 2>/dev/null | cut -d: -f1); do
      awk -v u="$u" '$1 == "user" && $2 == u {f=1} END {exit !f}' "$ACC" && continue
      if docker exec nas-samba-1 pdbedit -x "$u" >/dev/null; then echo "nas: deleted SMB account $u"; else echo "nas: could not delete SMB account $u"; fi
    done
    echo "SMB passwords set for: $(docker exec nas-samba-1 pdbedit -L 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
    ;;
  status)
    docker ps --filter name=nas-samba --format '{{.Names}}: {{.Status}}'
    echo "SMB passwords set for: $(docker exec nas-samba-1 pdbedit -L 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
    ;;
  *)
    echo "usage: hook.sh check | pre | post <mode> | status"; exit 1
    ;;
esac
