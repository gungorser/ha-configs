#!/bin/bash
# Removes LLDAP group memberships that the repo lists no longer give: for every user in
# /bootstrap/user-configs/*.json (users.json plus the Authelia service user), each group it is in
# but not listed under "groups" is taken away. Users and groups are never deleted (bootstrap.sh's
# DO_CLEANUP would also delete users made in the LLDAP UI), users not in the lists are not touched.
# Runs inside the LLDAP container (curl and jq come with bootstrap.sh), called by hook.sh post:
#   docker exec -i -e LLDAP_ADMIN_PASSWORD auth-lldap-1 bash -s < lldap-prune.sh
set -euo pipefail
URL=http://localhost:17170
TOKEN=$(jq -n --arg p "$LLDAP_ADMIN_PASSWORD" '{username: "admin", password: $p}' \
  | curl -sf -H 'Content-Type: application/json' -d @- "$URL/auth/simple/login" | jq -r .token)
[ -n "$TOKEN" ] && [ "$TOKEN" != null ] || { echo "prune: LLDAP login failed"; exit 1; }

gql() {  # gql <query> <variables json>
  jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}' \
    | curl -sf -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d @- "$URL/api/graphql"
}

cat /bootstrap/user-configs/*.json | jq -c 'select(.id) | {id, groups: (.groups // [])}' |
while read -r u; do
  id=$(jq -r .id <<<"$u")
  have=$(gql 'query($id: String!) { user(userId: $id) { groups { id displayName } } }' \
    "$(jq -n --arg id "$id" '{id: $id}')") || { echo "prune: cannot read $id"; continue; }
  jq -c --argjson want "$(jq .groups <<<"$u")" \
    '.data.user.groups[]? | select(.displayName as $g | $want | index($g) | not)' <<<"$have" |
  while read -r g; do
    gid=$(jq .id <<<"$g") name=$(jq -r .displayName <<<"$g")
    if gql 'mutation($u: String!, $g: Int!) { removeUserFromGroup(userId: $u, groupId: $g) { ok } }' \
         "$(jq -n --arg u "$id" --argjson g "$gid" '{u: $u, g: $g}')" | jq -e '.data.removeUserFromGroup.ok' >/dev/null; then
      echo "prune: removed $id from $name"
    else
      echo "prune: error removing $id from $name"
    fi
  done
done
