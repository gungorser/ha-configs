#!/bin/bash
# Stack hook for the paperless area (see docker-host/stack.sh), run on the docker VM as root from
# the area's folder: check | pre | post <mode> | status | share-all.
#   pre:  generates /opt/secrets/paperless.env once (secret key, DB password) and refreshes its
#         OIDC provider line from /opt/secrets/oidc/paperless.secret (made by the auth area);
#         prepares the folders.
#   post: waits for Paperless, ensures the groups admin (all permissions) and aile (documents).
#   share-all: after an import, makes every document, tag, correspondent, type, storage path
#         and custom field unowned, so all users with the group permissions see them.
set -euo pipefail
cd "$(dirname "$0")"
ENV=/opt/secrets/paperless.env
GPT_ENV=/opt/secrets/paperless-gpt.env
OIDC_SECRET=/opt/secrets/oidc/paperless.secret
DATA=/srv/data/paperless
DOCS=/srv/nas/dokuman/paperless
UID_=8003

rand() { openssl rand -hex "${1:-32}"; }
manage() { docker exec -i paperless-paperless-1 python3 manage.py "$@"; }

case "${1:-status}" in
  check)
    exit 0   # Paperless settings changed in its UI live in its DB, not in repo files
    ;;
  pre)
    [ -s "$OIDC_SECRET" ] || { echo "missing $OIDC_SECRET: deploy the auth area first"; exit 1; }
    if [ ! -s "$ENV" ]; then
      pw=$(rand 24)
      (umask 077; printf 'PAPERLESS_SECRET_KEY=%s\nPOSTGRES_PASSWORD=%s\nPAPERLESS_DBPASS=%s\n' "$(rand 32)" "$pw" "$pw" > "$ENV")
      echo "generated $ENV"
    fi
    providers=$(python3 -c '
import json, sys
print(json.dumps({"openid_connect": {"OAUTH_PKCE_ENABLED": True, "SCOPE": ["openid", "profile", "email", "groups"],
  "APPS": [{"provider_id": "authelia", "name": "Authelia", "client_id": "paperless", "secret": sys.argv[1],
            "settings": {"server_url": "https://auth.gungors.duckdns.org", "token_auth_method": "client_secret_basic"}}]}}))
' "$(cat "$OIDC_SECRET")")
    (umask 077; grep -v '^PAPERLESS_SOCIALACCOUNT_PROVIDERS=' "$ENV" > "$ENV.new"
     printf 'PAPERLESS_SOCIALACCOUNT_PROVIDERS=%s\n' "$providers" >> "$ENV.new")
    mv "$ENV.new" "$ENV" && chmod 600 "$ENV"
    [ -f "$GPT_ENV" ] || (umask 077; printf '# paperless-gpt (profile gpt): PAPERLESS_API_TOKEN, GOOGLEAI_API_KEY\n' > "$GPT_ENV")
    install -d -m 755 "$DATA" "$DOCS"
    install -d -m 750 -o "$UID_" -g "$UID_" "$DATA/data" "$DOCS/media" "$DOCS/consume" "$DOCS/export"
    install -d -m 700 "$DATA/pgdata" "$DATA/redis" "$DATA/gpt" "$DATA/gpt/prompts" "$DATA/gpt/db"
    ;;
  post)
    for _ in $(seq 90); do
      [ "$(docker inspect -f '{{.State.Health.Status}}' paperless-paperless-1 2>/dev/null)" = healthy ] && break
      sleep 2
    done
    manage shell <<'PY'
from django.contrib.auth.models import Group, Permission
admin, _ = Group.objects.get_or_create(name="admin")
admin.permissions.set(Permission.objects.all())
aile, _ = Group.objects.get_or_create(name="aile")
skip = ("auth", "admin", "sessions", "contenttypes", "guardian", "socialaccount", "account",
        "mfa", "authtoken", "auditlog", "django_celery_results")
aile.permissions.set(Permission.objects.exclude(content_type__app_label__in=skip))
print(f"groups: admin {admin.permissions.count()} perms, aile {aile.permissions.count()} perms")
PY
    echo "paperless: running"
    ;;
  share-all)
    manage shell <<'PY'
from documents.models import Document, Tag, Correspondent, DocumentType, StoragePath, CustomField
for m in (Document, Tag, Correspondent, DocumentType, StoragePath, CustomField):
    n = m.objects.exclude(owner=None).update(owner=None)
    print(f"{m.__name__}: {n} made unowned")
PY
    ;;
  status)
    docker ps --filter name=paperless- --format '{{.Names}}: {{.Status}}'
    ;;
  *)
    echo "usage: hook.sh check | pre | post <mode> | status | share-all"; exit 1
    ;;
esac
