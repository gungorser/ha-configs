# docker-host

The base of the docker VM (VM 110 `docker`, 192.168.0.222, Debian 13, built by
`proxmox/docker-vm.sh`): packages, Docker Engine, the folder layout and the NAS disks. The
service stacks (`proxy`, `dns`, `auth`, ...) are their own areas on top of this one.

| What | Where on the VM |
|---|---|
| Base packages: `ca-certificates curl gnupg qemu-guest-agent unattended-upgrades` | apt |
| Docker Engine + buildx + compose plugin, from Docker's apt repo (key fingerprint checked) | `files/etc/apt/sources.list.d/docker.sources`, `/etc/apt/keyrings/docker.asc` |
| Docker daemon: `local` log driver (10 MB x 3), `live-restore` | `files/etc/docker/daemon.json` |
| Docker starts only with `/srv/data` mounted (the NAS shares are not required) | `files/etc/systemd/system/docker.service.d/10-srv-data.conf` |
| `set-duckdns-token`: asks for the Duck DNS token without echoing it and writes `/opt/secrets/duckdns.env` (600) | `files/usr/local/sbin/` |
| Blender 5.2.4 (blender.org tarball, sha256 pinned) in `/opt/blender-<version>`, `/opt/blender` links to it; user `blender` (home `/var/lib/blender`) | `setup.sh` |
| "MCP for Blender" add-on 1.7 (ahujasid/blender-mcp `addon.py` at commit `41a1843`, sha256 pinned) in the `blender` user's profile | `setup.sh` |
| `blender-mcp-start` / `blender-mcp-stop`: Blender under Xvfb in the transient unit `blender-mcp` (4 GB max, low CPU weight), add-on server on port 9876; never at boot | `files/usr/local/sbin/`, `files/usr/local/lib/blender-mcp/start_mcp.py` |
| Firewall: port 9876 only from the Proxmox host (own nftables table, Docker untouched) | `files/etc/nftables-blender-mcp.nft`, `blender-mcp-firewall.service` |
| Unattended Debian security upgrades, no automatic reboot; Docker upgraded by hand | `files/etc/apt/apt.conf.d/` |
| Compose stacks, repo files only | `/opt/stacks` (755 root) |
| Secrets, never in git: `/opt/secrets/<area>.env` (600) | `/opt/secrets` (700 root) |
| NAS disks (table in `proxmox/README.md`): `/srv/data` (service data), `/srv/nas/backup`, `/srv/nas/dokuman`, `/srv/nas/foto` | ext4 labelled with the LV name, fstab by UUID with `discard`; `fstrim.timer` on |

Each NAS disk is found by its stable path `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi<N>`
(scsi1-4 in `proxmox/docker-vm.sh`) and must carry its own label; a disk with another label or
filesystem stops the deploy. A disk is formatted only when it carries no filesystem, partition
table or other signature **and** its label is listed in `FORMAT_NAS` (first install, Sercan's
approval). After a VM rebuild the disks keep their filesystems and are only mounted again.

`stack.sh` here is the shared deploy of the stack areas (`proxy/`, later `auth/`, ...): it ships
`master:<area>` to `/opt/stacks/<area>`, runs `docker compose up -d` and the area's `hook.sh`
(see the header of `stack.sh`). Each stack area's `deploy.sh` calls it.

## Live target

The docker VM, as root via `sudo` over SSH (`sercan@192.168.0.222`, the local break-glass admin).
State in `/var/lib/ha-configs/docker-host`: `current/` (deployed tree), `prev/`, `.deployed` (commit).

## Deploy

On the Proxmox host as `claude` (not root), from the clone:
`docker-host/deploy.sh <mode>` with modes `status`, `deploy`, `force`, `rollback`. It fetches
`origin/master`, ships `master:docker-host` to the VM and runs `setup.sh apply` there.
`setup.sh` is idempotent: it only does what `setup.sh check` reports.
First install: `FORMAT_NAS="nas-data nas-backup nas-dokuman nas-foto" docker-host/deploy.sh deploy`.
`deploy` stops when a managed file under `files/` was edited on the VM (shows the diff).

## Check

- `docker-host/deploy.sh status`: deployed = master, no live edits, `setup.sh check` says in sync.
- On the VM: `sudo docker run --rm hello-world`, `docker compose version`,
  `findmnt /srv/data /srv/nas/backup /srv/nas/dokuman /srv/nas/foto` (`discard`), `systemctl is-active fstrim.timer docker`.

## Rollback

`docker-host/deploy.sh rollback` re-applies the previous tree (files, layout); packages that the
newer version installed stay installed. Run it again to undo the rollback.

## Don't

- Format, repartition or `wipefs` a NAS disk by hand; never set `FORMAT_NAS` on a rebuild.
- Put secrets in the repo or service data on the system disk (`/srv/data` only).
- Add users to the `docker` group (it is root); admins use `sudo`. Other users come from LLDAP
  (SSSD) once the auth area exists.
- Install Claude Code here: Claude runs on the Proxmox host and manages the VM over SSH.
- Start Blender at boot or leave it running: Claude starts it for a task (`sudo blender-mcp-start`)
  and stops it afterwards (`sudo blender-mcp-stop`); renders on the N100 CPU are slow.
