# Gungor Home Assistant config

YAML of the Gungor house's Home Assistant: packages, YAML dashboards and own blueprints. The repository
is cloned on Home Assistant at `/config/gungors/`. `configuration.yaml` (not in the repository) loads it:

```yaml
homeassistant:
  packages: !include_dir_named gungors/packages
automation ui: !include automations.yaml     # automations made in the UI stay there
```

Related repositories: `ha-integrations` (custom platforms `gungors`: wrapper covers and sync
thermostats used in `covers.yaml` / `heating.yaml`), `ha-dashboards` (custom cards used by the
dashboards), `ha-floorplan` (Blender renders and the page behind `floorplan_3d.yaml`).

## Layout

```
packages/<topic>.yaml          one package per topic (file name = package name), any domains mixed
dashboards/<name>.yaml         YAML-mode dashboards, registered in packages/dashboards.yaml
blueprints/automation/*.yaml   own blueprints, used as  path: gungorser/<name>.yaml
blueprints/template/*.yaml
```

| package | what it does |
|---|---|
| `banyo_humidity` | bathroom fan on above 45 % humidity |
| `certificate` | renews the Let's Encrypt certificate (TJ-developer blueprint, lives only on HA) |
| `covers` | manual covers (input_number + template cover), `gungors` window_guard / timed_curtain wrappers, group `cover.yatak_cover`, `script.cover_tap` (moving -> stop, closed -> open, else close) |
| `dashboards` | Lovelace resources and the YAML dashboard registry |
| `heating` | `gungors` sync thermostats per room, `binary_sensor.kombi_talebi` and the boiler relay automation |
| `lightsensors` | occupancy lights (blueprint `light_with_sensor`) |
| `nspanel` | salon NSPanel (Blackymas blueprint, lives only on HA) |
| `pushbuttons` | push button automations per room (blueprint `pushbutton`), `script.blink_light` |
| `roomstate` | room state switches (template blueprint `roomstate`): on while anything listed is on, off turns all off |
| `schedules` | calendar-driven heating and covers (event description JSON `room_name`, `temp`, `sleep_temp`, `darkness`); used by the Program card |
| `switchbuttons` | relay switch <-> light sync (blueprint `switchbutton`) |

| dashboard (sidebar) | file | cards |
|---|---|---|
| Floorplan | `floorplan.yaml` | old 2D floorplan (ha-floorplan card, button-card templates) |
| Floorplan 3D | `floorplan_3d.yaml` | `custom:gungors-floor-card`: page entity -> HA entity map, actions, lighting |
| Program | `program.yaml` | `custom:gungors-schedule-card` |
| Gereksiz | `unnecessary.yaml` | `custom:gungors-rooms-card` |

## Conventions

- Every file opens with a short English comment on what it does; commit messages in English.
- Automations moved from the UI into a package keep their original `id`, so entity history survives.
- Credentials only via `!secret` (`/config/secrets.yaml`, never committed). Deploy a package only after
  its secrets exist on HA; a missing secret breaks the config load.
- Integrations that can only be set up in the UI stay in the UI (e.g. Xiaomi Miot vacuums, Xiaomi Cloud
  Map Extractor).
- **Use the wrapper entities**, never the hidden originals: covers `cover.<room>_cover` (not
  `*_blind`/`*_curtain`), heating `climate.<room>_thermostat` (not the TRV `*_climate`). See
  `ha-integrations`.
- Manual covers (no motor) are an `input_number.<id>_position` backing a template `cover.<id>`; the
  `configs` view of `floorplan_3d.yaml` has their sliders.
- The entities that matter are the ones on the 2D `floorplan.yaml`; new dashboards map to those.

## floorplan_3d.yaml in short

One `custom:gungors-floor-card` with `floors:` (kat0, kat1, kat2) and `sun: sun.sun`. Per floor
`entities` maps each page entity id to an HA entity of the same domain (`none` = background,
`{entity: none, value: X}` = fixed value, `selectable: false` = background that still follows HA).
Action standard (same as `floorplan.yaml`): lights tap toggle / hold more-info (anchor `&light`),
covers tap `script.cover_tap` / hold more-info. Room brightness is set here too: card `lighting.default`
and per floor `rooms: {<zone>: {sun, covers}}`, per light `gain`. A page entity missing from the map
shows up top right on the page; an unknown id or a missing HA entity stops the card. Full card options:
the header of `ha-dashboards/dist/gungors-floor-card.js`.

## Deploying

1. Change on a branch, open a PR, merge to `main` when approved.
2. Apply to the live HA: read the live file first (it may be ahead), write it with the Home Assistant
   MCP (`ha_write_file`, path `gungors/<file>`), run `homeassistant.check_config`, reload the domain
   (automations, scripts, templates, input_numbers, `gungors.reload`) or restart, then check the
   entities. Nothing on HA pulls this repository automatically.
3. A dashboard that references a new entity goes in after the package that creates it.
