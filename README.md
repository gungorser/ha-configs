# ha-configs

Sercan's Home Assistant YAML, checked out on HA at `/config/gungors`. `configuration.yaml` (not in
this repository) loads `packages/` with `!include_dir_named gungors/packages`.

| Folder | What |
|---|---|
| `packages/<topic>.yaml` | One package per topic (file name = package name), any domains mixed |
| `dashboards/*.yaml` | YAML dashboards registered in `packages/dashboards.yaml` (`floorplan` = old 2D, `floorplan_3d`, `program`, `unnecessary`) |
| `blueprints/` | Own blueprints, used as `path: gungorser/<name>.yaml` |
| `esphome/` | ESPHome device YAMLs; `gungors_esphome_sync` (`packages/deploy.yaml`) copies them to `/config/esphome` after the pull, CI runs `esphome config` |
| `pyscript/` | Python automations for pyscript (settings in `packages/pyscript.yaml`), see `pyscript/README.md` |

- Each file opens with a short English comment saying what it does.
- UI automations moved into packages keep their `id`. Credentials only via `!secret`.
- `platform: gungors` comes from ha-integrations; the cards from ha-dashboards.

## Naming physical devices

Zigbee2MQTT devices that a gungors wrapper drives (the `link` targets in `packages/lights.yaml`,
`packages/covers.yaml` and `packages/heating.yaml`) are named in Z2M as:

`phys_<name>_<domain>`

- The `phys_` prefix marks a device as physical: it is hidden behind a wrapper and is never used
  directly by dashboards or automations. Home Assistant entity IDs cannot start with `_`, so
  `phys_` plays the role of Python's private `_` prefix.
- The suffix is the entity domain (`light`, `climate`, `cover`, ...), so two devices of different
  domains in the same room never collide.
- A number belongs to the name, before the domain: `phys_tavan2_light`, `phys_bahce1_light`.
- Physical devices have no area, neither the device nor its entities. The wrapper carries the area.
- Rename in Zigbee2MQTT (the device's friendly name), not in Home Assistant. Renaming in Home
  Assistant only changes the entity and is overwritten the next time Z2M re-publishes the device.
- Wrappers keep the room name without a prefix (`bebek_light`, `koridor1_light`).
- When a device is renamed, every reference to its entity IDs is updated in the same change:
  `link` values, blueprints, automations, dashboards and scripts.

Claude: YAML and cards are worked on by the main session (no agent); agent `pyscript`
(`.claude/agents/`) for pyscript automations. Rules and the other agents: [CLAUDE.md](CLAUDE.md).
