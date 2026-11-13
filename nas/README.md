# nas

Samba on the docker VM: the house's file shares on the NAS disks (`proxmox/README.md`), reachable
in the house at `\\192.168.0.222` (port 445 on the VM's LAN address only; the router forwards no SMB).

| Share | Path | Who | Notes |
|---|---|---|---|
| `backup` | `/srv/nas/backup` | group `admin` | backups (HA in `ha/`, later restic dumps) |
| `ha-backup` | `/srv/nas/backup/ha` | `ha-backup` (+ `admin`) | HA's network storage for its backups; sees only this folder |
| `dokuman` | `/srv/nas/dokuman/genel` | group `aile` | general documents; Paperless's own files on this disk are not shared |
| `tarama` | `/srv/nas/dokuman/paperless/consume` | group `aile` | scan inbox: Paperless consumes what lands here (files owned by `paperless`, uid 8003) |
| `foto` | `/srv/nas/foto` | group `aile` | photos; Immich gets a folder here later |

`melike` is in `aile` only, so she has no backup access. Guests and wrong passwords are refused;
SMB3 only, encryption when the client supports it.

### Users and passwords

- Names, uids/gids and groups come from LLDAP's lists in the repo
  (`auth/lldap-bootstrap`); `hook.sh` writes them to `/srv/data/nas/accounts` and the container
  creates matching local accounts (no login). Service accounts: `ha-backup` (uid 10100, SMB only)
  and `paperless` (uid 8003, the scan inbox owner).
- SMB cannot check LLDAP passwords (LLDAP keeps no NT hashes; its Samba integration is still open
  upstream), so each person has a separate NAS password in Samba's passdb
  (`/srv/data/nas/samba`). Set it with `ssh -t sercan@192.168.0.222 sudo set-smb-password <user>`
  (silent prompt, 12+ characters). A user without one cannot log in to the shares.
- Change passwords only with `sudo set-password <user>`: one prompt sets the LLDAP and the NAS
  password together, so a person has one password (a change in the LLDAP web UI would not reach
  Samba). `set-ldap-password` and `set-smb-password` hand people over to it; `set-smb-password`
  alone is only for service accounts without LLDAP login (`ha-backup`).

## Live target

`/opt/stacks/nas` on the docker VM (image built there from `Dockerfile`: Debian trixie-slim pinned
by digest + Debian's samba), `/srv/data/nas` (accounts, passdb), the folders above.

## Deploy

`nas/deploy.sh <mode>` on the Proxmox host as `claude` (shared `docker-host/stack.sh`). Deploy
`auth` first (the account lists come from it). A new person: add them in
`auth/lldap-bootstrap`, deploy auth and nas, then `set-smb-password`.

## Check

- `nas/deploy.sh status`: container healthy, the users with an SMB password listed.
- From a PC: `\\192.168.0.222\dokuman` with the NAS password opens; `\\192.168.0.222\backup`
  opens for admins only.

## Rollback

`nas/deploy.sh rollback`. Files on the disks and the passdb are untouched by deploys.

## Don't

- Share `/srv/nas/dokuman/paperless` (media) or `/srv/data` over SMB.
- Publish port 445 on all addresses or through the router.
