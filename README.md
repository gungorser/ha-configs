# ha-configs

Sercan's Home Assistant config and the config of the add-ons around it. **Each top folder with a
`deploy.sh` is an area: one live target, its own deploy, its own README** (read only the README of
the area you change).

| Area | Live target | Deploy | README |
|---|---|---|---|
| `gungors/` | `/config/gungors` (`packages/`, `dashboards/`) | swap, then reload or restart | [gungors/README.md](gungors/README.md) |
| `pyscript/` | `/config/pyscript` | swap, then `pyscript.reload` | [pyscript/README.md](pyscript/README.md) |
| `blueprints/` | `/config/blueprints/{automation,template}/gungorser` | swap, then reload | [blueprints/README.md](blueprints/README.md) |
| `esphome/` | `/config/esphome` (ESPHome Device Builder) | writes our files only | [esphome/README.md](esphome/README.md) |
| `proxmox/` | Proxmox host `pve` (`/etc/pve/storage.cfg`, systemd unit) + VM rebuild scripts | `sudo proxmox/deploy.sh` on the host (not `configs_deploy`) | [proxmox/README.md](proxmox/README.md) |
| `docker-host/` | docker VM 110 (packages, Docker, `/opt/stacks`, `/opt/secrets`, `/srv/data`, `/srv/nas/*` = NAS disks) | `docker-host/deploy.sh` on the Proxmox host (SSH) | [docker-host/README.md](docker-host/README.md) |
| `proxy/` | docker VM `/opt/stacks/proxy` (NPM + Duck DNS updater), NPM hosts via its API | `proxy/deploy.sh` on the Proxmox host (`docker-host/stack.sh`) | [proxy/README.md](proxy/README.md) |

## How deploy works (all areas)

- On HA the repository is a bare clone, `/config/.ha-configs.git` (no checkout).
- Everything runs through the HA MCP (no terminal):
  `ha_call_service(shell_command, <name>, <data>, return_response=true)`, defined in
  `gungors/packages/shell_command.yaml`:
  - `configs_status`: fetch master, then per area the deployed commit, master and live edits.
  - `configs_deploy` with `{"area": "<area>", "mode": "<mode>"}`: fetches master and runs
    `<area>/deploy.sh` from git. Modes: `deploy` (default; stops and shows the diff when the live
    target was edited), `force` (overwrites live edits, Sercan's approval only), `rollback`
    (restores the previous version; again to undo).
- `swap.sh` is the shared "swap" deploy: unpack `master:<area>` into
  `/config/.ha-configs-stage/`, `mv` it over the target, keep the old one in
  `/config/.ha-configs-prev/`, write the commit to `<target>/.deployed`. Files removed from the
  repo disappear live.
- A new area: a top folder with `deploy.sh` (modes `status`, `deploy`, `force`, `rollback`) and a
  README with the sections Live target, Deploy, Check, Rollback, Don't.
- Change files only through a PR. Never write deployed files live (`ha_write_file`): the next
  deploy stops on them.

## Naming physical devices

Zigbee2MQTT devices that a gungors wrapper drives (the `link` targets in `gungors/packages/light.yaml`,
`gungors/packages/cover.yaml` and `gungors/packages/climate.yaml`) are named in Z2M as:

`phys_<name>_<domain>`

- The `phys_` prefix marks a device as physical: it is hidden behind a wrapper and is never used
  directly by dashboards or automations. Home Assistant entity IDs cannot start with `_`, so
  `phys_` plays the role of Python's private `_` prefix.
- The suffix is the entity domain (`light`, `climate`, `cover`, ...), so two devices of different
  domains in the same room never collide.
- A number belongs to the name, before the domain: `phys_tavan2_light`, `phys_veranda1_light`.
- Physical devices have no area, neither the device nor its entities. The wrapper carries the area.
- Rename in Zigbee2MQTT (the device's friendly name), not in Home Assistant. Renaming in Home
  Assistant only changes the entity and is overwritten the next time Z2M re-publishes the device.
- Wrappers are named by the room alone, without a prefix or a domain suffix: the domain is
  already in the entity ID (`light.bebek`, `climate.bebek`, `cover.yatak_window`, `event.bebek`).
  Wrappers have no device, so equal names in different domains do not collide. Their friendly
  name is set in Home Assistant, readable Turkish (`Bebek ışığı`); `unique_id` keeps the old name.
- When a device is renamed, every reference to its entity IDs is updated in the same change:
  `link` values, blueprints, automations, dashboards and scripts.

- Each file opens with a short English comment saying what it does.
- UI automations moved into packages keep their `id`. Credentials only via `!secret`.
- `platform: gungors` comes from ha-integrations; the cards from ha-dashboards.

Claude: YAML and cards are worked on by the main session (no agent); agent `pyscript`
(`.claude/agents/`) for pyscript automations. Rules and the other agents: [CLAUDE.md](CLAUDE.md).
