# proxmox

The Proxmox VE host `pve` (192.168.0.220, Beelink S12 Pro, N100, 16 GB, 512 GB SATA SSD) and the
scripts that rebuild its two VMs from scratch. The VMs hold no data of their own: config comes from
this repo, NAS and service data live on four thin LVs that belong to no VM.

| File | What |
|---|---|
| `host/storage.cfg` | `/etc/pve/storage.cfg`: `local` (ISOs, images, snippets) and `local-lvm` (thin pool `pve/data`) |
| `host/claude-remote-control.service` | Claude Code Remote Control as a systemd unit (user `claude`) |
| `host/claude-work-mcp.json` | `/home/claude/work/.mcp.json`: MCP server `blender` (`uvx blender-mcp==2.0.0`, `BLENDER_HOST=192.168.0.222`, port 9876) for Claude Code |
| `host/claude-work-settings.json` | `/home/claude/work/.claude/settings.json`: enables that server without a prompt |
| `host/interfaces` | `/etc/network/interfaces`, **reference only**, never deployed |
| `nas-disks.sh` | Creates the NAS thin LVs (table below) if missing; never formats or resizes an existing one |
| `docker-vm.sh` | VM 110 `docker`: Debian 13 cloud image, cloud-init, NAS disks attached as scsi1-4 |
| `haos-vm.sh` | VM 100 `haos`: official HAOS qcow2, UEFI, Zigbee dongle by vid:pid |
| `cloud-init/docker-vm-vendor.yaml` | Vendor data for VM 110 (installs the guest agent) |
| `lib.sh` | Shared helpers (asks before destroying an existing VM) |

| VM | vCPU (cpuunits) | RAM min-max (shares) | Disk | MAC | IP | Boot |
|---|---|---|---|---|---|---|
| 110 docker | 4 (1024) | 6-12 GB (1000) | 32G + NAS disks `scsi1-4` [+ SSD2 `scsi5`] | `02:00:C0:A8:00:DE` | 192.168.0.222 static (cloud-init) | order 1 |
| 100 haos | 4 (2048) | 4-8 GB (2000) | 32G | `02:00:C0:A8:00:DD` | 192.168.0.221 (router DHCP reservation on the MAC) | order 2, up 30 |

NAS disks (thin LVs in `pve/data`, grown with `lvextend` + `resize2fs` at 80 %):

| LV | Size | VM 110 | Mount | Holds | Samba share (later), access |
|---|---|---|---|---|---|
| `nas-data` | 30G | `scsi1` | `/srv/data` | service data (databases, app state) | none |
| `nas-backup` | 100G | `scsi2` | `/srv/nas/backup` | HA backups, restic service backups | `backup`: admins + services |
| `nas-dokuman` | 50G | `scsi3` | `/srv/nas/dokuman` | Paperless, general documents | `dokuman`: family |
| `nas-foto` | 150G | `scsi4` | `/srv/nas/foto` | Immich library | `foto`: family |

`nas-backup` on the same SSD guards against mistakes, not a disk failure: it moves to SSD2 once
that disk is fitted.

## Live target

The Proxmox host itself, as root. The repo is cloned at `/home/claude/work/ha-configs`
(deploy key `~claude/.ssh/ha-configs_deploy`, host alias `github-ha-configs`). `deploy.sh` keeps its
state in `/var/lib/ha-configs/proxmox` (`.deployed` = commit, `prev/` = files before the last deploy).

## Deploy

Host files: `sudo proxmox/deploy.sh <mode>` (fetches `origin/master` itself; modes `status`,
`deploy`, `force`, `rollback`). `deploy` writes the files of `host/` (except `interfaces`) when they
changed, installs the pinned `uv`/`uvx` into `~claude/.local/bin` when missing, then reloads systemd. It never restarts `claude-remote-control` (that is the session
running it): a unit change applies at the next reboot or by hand.

VMs, in this order (HA backups live on the NAS, i.e. the docker VM):

1. `sudo proxmox/nas-disks.sh` (no-op for the LVs that exist).
2. `sudo SSH_KEYS=<public keys file> proxmox/docker-vm.sh`, then the `docker-host` area on the VM
   (Docker, mounting the NAS disks, services). Optional `SSD2=/dev/disk/by-id/...`
   attaches the backup disk whole, unformatted.
3. `sudo proxmox/haos-vm.sh`: HAOS 18.4 pinned (sha256 checked), Zigbee dongle
   `1a86:55d4` (SONOFF Dongle Plus V2 / ZBDongle-E) passed through, optional `BT_USB=8087:0026`.
   Created stopped with `onboot 0`: it takes over the Pi's 192.168.0.221, so it is started only at
   the cutover after the Pi is off (`START=1 ONBOOT=1`, or `qm set 100 --onboot 1; qm start 100`),
   then the latest HA backup is restored in onboarding.

Both VM scripts download and verify their image into `/var/lib/vz/import` and ask
(`destroy <name>`) before deleting an existing VM; disks attached by a `/dev` path (NAS disks, SSD2)
are detached first and never deleted. `VMID=`, `NAME=`, `IP=`, `MAC=` and `NO_START=1` override
the defaults for a test build (monthly test: `docker-vm.sh` with a spare id and IP, then delete it;
give the test VM its own MAC and none of the NAS disks).

## Check

- `sudo proxmox/deploy.sh status`: deployed commit = master, no live edits, no `interfaces` diff.
- `qm config 110` / `qm config 100` match the table above; `qm agent <id> ping` answers.
- `lvs pve` shows the four `nas-*` LVs; `systemctl is-active claude-remote-control` is `active`.

## Rollback

`sudo proxmox/deploy.sh rollback` restores the host files from before the last deploy. A VM is
rolled back by rebuilding it with its script (its data is on the NAS disks or in backups).

## Don't

- Format, resize down or `lvremove` a `nas-*` LV, or attach one to two running VMs at once.
- Rename a `nas-*` LV to a `vm-<id>-*` name: Proxmox would then delete it with that VM.
- Edit `storage.cfg` or the unit by hand on the host: the next deploy stops on it.
- Change `/etc/network/interfaces` remotely without a console at hand.
