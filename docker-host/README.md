# docker-host

The base of the docker VM (VM 110 `docker`, 192.168.0.222, Debian 13, built by
`proxmox/docker-vm.sh`): packages, Docker Engine, the folder layout and the nas-data disk. The
service stacks (`proxy`, `dns`, `auth`, ...) are their own areas on top of this one.

| What | Where on the VM |
|---|---|
| Base packages: `ca-certificates curl gnupg qemu-guest-agent unattended-upgrades` | apt |
| Docker Engine + buildx + compose plugin, from Docker's apt repo (key fingerprint checked) | `files/etc/apt/sources.list.d/docker.sources`, `/etc/apt/keyrings/docker.asc` |
| Docker daemon: `local` log driver (10 MB x 3), `live-restore` | `files/etc/docker/daemon.json` |
| Docker starts only with `/srv/data` mounted | `files/etc/systemd/system/docker.service.d/10-srv-data.conf` |
| Unattended Debian security upgrades, no automatic reboot; Docker upgraded by hand | `files/etc/apt/apt.conf.d/` |
| Compose stacks, repo files only | `/opt/stacks` (755 root) |
| Secrets, never in git: `/opt/secrets/<area>.env` (600) | `/opt/secrets` (700 root) |
| Service data, NAS, HA backups | `/srv/data` = nas-data (ext4, label `nas-data`), fstab by UUID with `discard`; `fstrim.timer` on |

The nas-data disk is found by its stable path `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`
(scsi1 in `proxmox/docker-vm.sh`). It is formatted only when it carries no filesystem, partition
table or other signature **and** `FORMAT_NAS_DATA=1` is given (first install, Sercan's approval).
After a VM rebuild the disk keeps its filesystem and is only mounted again.

## Live target

The docker VM, as root via `sudo` over SSH (`sercan@192.168.0.222`, the local break-glass admin).
State in `/var/lib/ha-configs/docker-host`: `current/` (deployed tree), `prev/`, `.deployed` (commit).

## Deploy

On the Proxmox host as `claude` (not root), from the clone:
`docker-host/deploy.sh <mode>` with modes `status`, `deploy`, `force`, `rollback`. It fetches
`origin/master`, ships `master:docker-host` to the VM and runs `setup.sh apply` there.
`setup.sh` is idempotent: it only does what `setup.sh check` reports.
First install: `FORMAT_NAS_DATA=1 docker-host/deploy.sh deploy`.
`deploy` stops when a managed file under `files/` was edited on the VM (shows the diff).

## Check

- `docker-host/deploy.sh status`: deployed = master, no live edits, `setup.sh check` says in sync.
- On the VM: `sudo docker run --rm hello-world`, `docker compose version`,
  `findmnt /srv/data` (nas-data, `discard`), `systemctl is-active fstrim.timer docker`.

## Rollback

`docker-host/deploy.sh rollback` re-applies the previous tree (files, layout); packages that the
newer version installed stay installed. Run it again to undo the rollback.

## Don't

- Format, repartition or `wipefs` nas-data by hand; never set `FORMAT_NAS_DATA=1` on a rebuild.
- Put secrets in the repo or service data on the system disk (`/srv/data` only).
- Add users to the `docker` group (it is root); admins use `sudo`. Other users come from LLDAP
  (SSSD) once the auth area exists.
- Install Blender or Claude Code here: Claude runs on the Proxmox host and manages the VM over SSH.
