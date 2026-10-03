# ha-configs

Sercan's Home Assistant YAML. It is checked out on Home Assistant at `/config/gungors/`.
`configuration.yaml` (not in this repo) loads it with
`homeassistant: packages: !include_dir_named gungors/packages` and keeps
`automation ui: !include automations.yaml` for UI automations.

## Layout

| Path | What |
|---|---|
| `packages/<topic>.yaml` | One package per topic (file name = package name), any domains mixed. Each file opens with a comment saying what it does: read that header first. |
| `dashboards/*.yaml` | YAML-mode dashboards, registered in `packages/dashboards.yaml` (`filename: gungors/dashboards/<file>`): `floorplan` (old 2D), `floorplan_3d` (3D floor view), `program`, `unnecessary` ("Gereksiz") |
| `blueprints/automation/`, `blueprints/template/` | Own blueprints, used as `path: gungorser/<name>.yaml`: light_with_sensor, pushbutton, switchbutton, roomstate |

Packages: banyo_humidity, certificate, covers (gungors window_guard / timed_curtain covers + template
covers), dashboards (Lovelace resources + YAML dashboard registry), heating (gungors sync
thermostats, demand sensor, boiler relay), lightsensors, nspanel, pushbuttons, roomstate, schedules
(calendar-driven climate/cover), switchbuttons.

## Conventions

- English comments and commit messages.
- UI automations moved into a package keep their original `id`, so entity history survives.
- Credentials only through `!secret` (`/config/secrets.yaml`, never committed). Claude cannot read
  or write secrets: Sercan adds a new secret first, then the package that uses it is deployed (a
  missing secret breaks the config load).
- Integrations that are UI-only stay in the UI (e.g. Xiaomi Miot vacuums, Xiaomi Cloud Map
  Extractor v3).
- Third-party blueprints (Blackymas NSPanel, TJ-developer certificate) live only on HA.

## Deploying

Change on a branch -> Sercan approves -> write the file to HA (Home Assistant MCP `ha_write_file`
under `gungors/`) -> reload the domain or restart -> Sercan tests. Ask before editing live config.
Branches: pull requests merge into `main`.

## Related repositories

- **ha-integrations**: the `gungors` platforms configured in `packages/covers.yaml` and
  `packages/heating.yaml`. Dashboards and automations use the wrapper entities, never the hidden
  originals.
- **ha-floorplan**: renders the 3D floor view; `dashboards/floorplan_3d.yaml` maps its page ids to
  entities (the page/card protocol is documented in ha-floorplan).
- **ha-dashboards**: the custom cards used by the dashboards (`custom:gungors-floor-card`, ...).
