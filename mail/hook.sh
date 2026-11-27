#!/bin/bash
# Stack hook for the mail area (see docker-host/stack.sh), run on the docker VM as root:
# check | pre | post <mode> | status.
#   pre:  data folders, and /opt/secrets/mail.env (LDAP_BIND_PW) from auth's sssd bind user.
#   post: waits for the mail server to listen on port 25.
set -euo pipefail
cd "$(dirname "$0")"
ENV=/opt/secrets/mail.env
DATA=/srv/data/mail

case "${1:-status}" in
  check) exit 0 ;;
  pre)
    [ -s /opt/secrets/auth/sssd_password ] || { echo "auth area is not deployed (no sssd bind user)"; exit 1; }
    install -d -m 755 "$DATA" "$DATA/data" "$DATA/state" "$DATA/logs" "$DATA/config"
    install -d -m 777 "$DATA/roundcube"   # Roundcube's www-data writes its SQLite file here
    (umask 077; printf 'LDAP_BIND_PW=%s\n' "$(cat /opt/secrets/auth/sssd_password)" > "$ENV.new") && mv "$ENV.new" "$ENV"
    chmod 600 "$ENV"
    ;;
  post)
    for i in $(seq 1 60); do
      [ "$(docker inspect -f '{{.State.Health.Status}}' mail-mailserver-1 2>/dev/null)" = healthy ] && { echo "mail: server listening on 25"; exit 0; }
      sleep 3
    done
    docker logs --tail 40 mail-mailserver-1 2>&1 | sed 's/^/  /'; exit 1
    ;;
  status)
    docker inspect -f 'mail-mailserver-1: {{.State.Status}} {{.State.Health.Status}}' mail-mailserver-1 2>/dev/null || echo "mail-mailserver-1: missing"
    ;;
  *) echo "usage: hook.sh check | pre | post <mode> | status"; exit 1 ;;
esac
