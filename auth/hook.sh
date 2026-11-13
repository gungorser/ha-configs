#!/bin/bash
# Stack hook for the auth area (see docker-host/stack.sh), run on the docker VM as root from the
# area's folder: check | pre | post <mode> | status.
#   pre:  generates the secrets once (never overwritten), assembles the LLDAP bootstrap folder,
#         prepares the data folders and installs set-ldap-password.
#   post: waits for LLDAP, applies users, groups and the POSIX attribute schema from
#         lldap-bootstrap/ (adds and updates, never deletes), then waits for Authelia.
set -euo pipefail
cd "$(dirname "$0")"
ENV=/opt/secrets/auth.env
SEC=/opt/secrets/auth
DATA=/srv/data/auth
LLDAP_UID=8001
AUTHELIA_UID=8002

rand() { openssl rand -hex "${1:-32}"; }

# secret <file> <owner uid> <command...>: writes the command's output once, mode 600.
secret() {
  local f=$1 owner=$2; shift 2
  if [ ! -s "$f" ]; then
    (umask 077; "$@" > "$f.new") && mv "$f.new" "$f"
    echo "generated $f"
  fi
  chown "$owner:$owner" "$f" && chmod 600 "$f"
}

env_value() { sed -n "s/^$1=//p" "$ENV"; }

# oidc_client <client_id>: a confidential OIDC client's secret, made once. The plain secret goes to
# /opt/secrets/oidc/<client_id>.secret (root, read by that service's hook), its PBKDF2 digest to
# the Authelia secrets folder (read by configuration.yml through the template filter).
oidc_client() {
  local c=$1 out
  install -d -m 700 /opt/secrets/oidc
  if [ ! -s "/opt/secrets/oidc/$c.secret" ] || [ ! -s "$SEC/authelia/oidc_$c.digest" ]; then
    out=$(docker run --rm "$(sed -n 's/^ *image: *\(authelia\/authelia:.*\)$/\1/p' compose.yaml)" \
      authelia crypto hash generate pbkdf2 --random --random.length 64 --random.charset alphanumeric)
    (umask 077
     printf '%s\n' "$out" | sed -n 's/^Random Password: //p' > "/opt/secrets/oidc/$c.secret"
     printf '%s\n' "$out" | sed -n 's/^Digest: //p' > "$SEC/authelia/oidc_$c.digest")
    if [ ! -s "/opt/secrets/oidc/$c.secret" ] || [ ! -s "$SEC/authelia/oidc_$c.digest" ]; then
      echo "OIDC secret for $c failed"; exit 1
    fi
    echo "generated OIDC client secret for $c"
  fi
  chmod 600 "/opt/secrets/oidc/$c.secret"
  chown "$AUTHELIA_UID:$AUTHELIA_UID" "$SEC/authelia/oidc_$c.digest" && chmod 600 "$SEC/authelia/oidc_$c.digest"
}

healthy() {  # healthy <container> <seconds>
  local i
  for ((i = 0; i < $2; i += 2)); do
    case "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null)" in
      healthy|running) return 0 ;;
    esac
    sleep 2
  done
  echo "$1 not healthy after $2 s"; docker logs --tail 30 "$1" 2>&1 | sed 's/^/  /'
  return 1
}

case "${1:-status}" in
  check)
    exit 0   # users edited in the LLDAP UI are not drift: the repo list only adds and updates
    ;;
  pre)
    install -d -m 700 -o root -g root "$SEC"
    install -d -m 700 -o "$AUTHELIA_UID" -g "$AUTHELIA_UID" "$SEC/authelia"
    if [ ! -s "$ENV" ]; then
      (umask 077; printf 'LLDAP_JWT_SECRET=%s\nLLDAP_KEY_SEED=%s\nLLDAP_LDAP_USER_PASS=%s\n' \
        "$(rand)" "$(rand)" "$(rand 24)" > "$ENV")
      echo "generated $ENV"
    fi
    chmod 600 "$ENV"
    secret "$SEC/authelia/jwt_secret" "$AUTHELIA_UID" rand 32
    secret "$SEC/authelia/session_secret" "$AUTHELIA_UID" rand 32
    secret "$SEC/authelia/storage_key" "$AUTHELIA_UID" rand 32
    secret "$SEC/authelia/ldap_password" "$AUTHELIA_UID" rand 24
    secret "$SEC/authelia/oidc_hmac_secret" "$AUTHELIA_UID" rand 32
    secret "$SEC/authelia/oidc_jwks_rs256.pem" "$AUTHELIA_UID" openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -quiet
    oidc_client paperless
    oidc_client immich
    # LLDAP bootstrap folder: the repo lists plus the Authelia service user (with its password).
    rm -rf "$SEC/bootstrap.new" && cp -a lldap-bootstrap "$SEC/bootstrap.new"
    printf '{"id": "authelia", "email": "authelia@gungors.duckdns.org", "displayName": "Authelia (service)", "groups": ["lldap_password_manager"], "password": "%s"}\n' \
      "$(cat "$SEC/authelia/ldap_password")" > "$SEC/bootstrap.new/user-configs/zz-authelia.json"
    chown -R "$LLDAP_UID:$LLDAP_UID" "$SEC/bootstrap.new" && chmod -R go-rwx "$SEC/bootstrap.new"
    rm -rf "$SEC/bootstrap" && mv "$SEC/bootstrap.new" "$SEC/bootstrap"
    install -d -m 750 -o root -g root "$DATA"
    install -d -m 700 -o "$LLDAP_UID" -g "$LLDAP_UID" "$DATA/lldap"
    install -d -m 700 -o "$AUTHELIA_UID" -g "$AUTHELIA_UID" "$DATA/authelia"
    chmod 755 "$DATA"
    install -m 755 set-ldap-password /usr/local/sbin/set-ldap-password
    ;;
  post)
    healthy auth-lldap-1 120
    docker exec -e LLDAP_ADMIN_PASSWORD="$(env_value LLDAP_LDAP_USER_PASS)" auth-lldap-1 /app/bootstrap.sh \
      | grep -vE '^\s*$' | grep -iE 'error|created|updated|added|successfully' || true
    # On a first deploy Authelia starts before its LDAP service user exists and restarts in a loop
    # until bootstrap.sh has created it; restart it once so only this start's log counts.
    since=$(date +%s)
    docker restart auth-authelia-1 >/dev/null
    healthy auth-authelia-1 120
    docker logs --since "$since" auth-authelia-1 2>&1 | grep -iE 'level=(error|fatal)' && exit 1
    echo "auth: LLDAP bootstrapped, Authelia running"
    ;;
  status)
    for c in auth-lldap-1 auth-authelia-1; do
      echo "$c: $(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null || echo missing)"
    done
    ;;
  *)
    echo "usage: hook.sh check | pre | post <mode> | status"; exit 1
    ;;
esac
