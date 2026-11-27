# nas

Samba on the docker VM: the house's file shares on the NAS disks (`proxmox/README.md`), reachable
in the house at `\\192.168.0.222` (port 445 on the VM's LAN address only; the router forwards no SMB).

| Share | Path | Who | Notes |
|---|---|---|---|
| `ha-backup` | `/srv/nas/backup/ha` | `ha-backup` | HA's network storage for its backups; sees only this folder |
| `muzik` | `/srv/nas/foto/muzik` | `ha-media` (read-only) | songs for the TV's background music; HA mounts it as network storage `muzik` (usage media) for Music Assistant |
| `floorplan` | `/srv/nas/foto/floorplan` | `ha-media` (read-only) | the 3D floor page and renders (written on the VM by the floorplan deploy); HA mounts it as network storage `floorplan` (usage share) and `configs_deploy` area `floorplan` copies it to `/config/www` |

Only service accounts log in (since 2026-11-27, Sercan's decision): people use Immich, Paperless
and HA through Authelia and have no NAS account. The shares `backup`, `dokuman`, `tarama` and
`foto` were removed then; their folders stay on the disks (reach them with ssh on the VM). Songs
for `muzik` are copied in on the VM (group `aile`, 2775). Guests and wrong passwords are refused;
SMB3 only, encryption when the client supports it.

### Users and passwords

- `hook.sh` writes `/srv/data/nas/accounts`: the groups from LLDAP's lists (`auth/lldap-bootstrap`,
  folder owners only) and as users only the service accounts: LLDAP group `servis` (`ha-media`),
  `ha-backup` (uid 10100) and `paperless` (uid 8003, the scan inbox owner, no SMB password). The
  container creates matching local accounts (no login). On deploy, `hook.sh post` deletes SMB
  passwords of accounts no longer listed (`pdbedit -x`).
- Samba keeps its own passdb (`/srv/data/nas/samba`); LLDAP's OPAQUE passwords cannot be synced to
  it, so NAS passwords are separate. Set them with
  `ssh -t sercan@192.168.0.222 sudo set-password <service account>` (silent prompt, twice, 12+
  characters); it changes only the NAS password and refuses people. `set-smb-password` is a
  wrapper for it. People's login passwords: `set-ldap-password` (auth area).

## Live target

`/opt/stacks/nas` on the docker VM (image built there from `Dockerfile`: Debian trixie-slim pinned
by digest + Debian's samba), `/srv/data/nas` (accounts, passdb), the folders above. `/srv/nas/foto` is
2771 (others may only pass through, for `ha-media` to reach `muzik/`).

## Deploy

`nas/deploy.sh <mode>` on the Proxmox host as `claude` (shared `docker-host/stack.sh`). Deploy
`auth` first (the group lists come from it). A new service account: add it to LLDAP group
`servis` in `auth/lldap-bootstrap`, deploy auth and nas, then `set-password <user>`.

## Check

- `nas/deploy.sh status`: container healthy, the users with an SMB password listed.
- HA: Settings -> System -> Storage shows `muzik`, `floorplan` and the backup storage connected.

## Rollback

`nas/deploy.sh rollback`. Files on the disks and the passdb are untouched by deploys.

## Don't

- Share `/srv/nas/dokuman/paperless` (media) or `/srv/data` over SMB.
- Publish port 445 on all addresses or through the router.
