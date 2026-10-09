# ha-configs

Sercan's Home Assistant YAML, checked out on HA at `/config/gungors`. `configuration.yaml` (not in
this repository) loads `packages/` with `!include_dir_named gungors/packages`.

| Folder | What |
|---|---|
| `packages/<topic>.yaml` | One package per topic (file name = package name), any domains mixed |
| `dashboards/*.yaml` | YAML dashboards registered in `packages/dashboards.yaml` (`floorplan` = old 2D, `floorplan_3d`, `program`, `unnecessary`) |
| `blueprints/` | Own blueprints, used as `path: gungorser/<name>.yaml` |

- Each file opens with a short English comment saying what it does.
- UI automations moved into packages keep their `id`. Credentials only via `!secret`.
- `platform: gungors` comes from ha-integrations; the cards from ha-dashboards.

Claude agent: `config` (`.claude/agents/`); rules and the other agents: [CLAUDE.md](CLAUDE.md).
