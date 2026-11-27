#!/bin/sh
# Creates the local groups and users listed in /etc/nas/accounts (written by hook.sh from the
# LLDAP lists, so names and ids match LLDAP), then runs smbd. SMB passwords live in Samba's own
# passdb (/var/lib/samba, set with set-smb-password); these accounts have no login.
# accounts lines: group <name> <gid>  |  user <name> <uid> <primary gid> <group,group,...>
set -eu
while read -r kind name id gid groups; do
  case "$kind" in
    group) getent group "$name" >/dev/null || groupadd -g "$id" "$name" ;;
    user)
      getent passwd "$name" >/dev/null || useradd -M -d /nonexistent -s /usr/sbin/nologin -u "$id" -g "$gid" "$name"
      [ -z "${groups:-}" ] || usermod -G "$groups" "$name"
      ;;
  esac
done < /etc/nas/accounts
mkdir -p /var/lib/samba/private /var/cache/samba /run/samba
exec smbd --foreground --no-process-group --debug-stdout
