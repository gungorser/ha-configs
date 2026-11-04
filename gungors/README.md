# gungors (HA packages)

## Live target
`/config/gungors`. `configuration.yaml` (not in this repository) loads it with
`homeassistant: packages: !include_dir_named gungors`.

- `<topic>.yaml`: one package per topic (file name = package name), any domains mixed.
- `dashboards/<name>.yml`: YAML dashboards, registered in `dashboards.yaml`
  (`filename: gungors/dashboards/<name>.yml`; `floorplan` = old 2D, `floorplan_3d`, `program`,
  `unnecessary`).
- `deploy.yaml`: the deploy shell_commands for all areas (root README).

## Deploy
`configs_deploy` with `{"area": "gungors"}` (shared swap, `../swap.sh`). Then reload what changed
(automation, script, template, ... or `gungors.reload`), or restart for domains without a reload.
Run HA's config check before a restart. Dashboards only need a browser refresh.

## Check
`ha_get_logs`, the changed entities, the dashboards open. `configs_status` shows no live edits.

## Rollback
`configs_deploy` with `{"area": "gungors", "mode": "rollback"}`, then the same reload or restart.

## Don't
- Put any other `*.yaml` under this folder: `!include_dir_named` loads every `*.yaml` here, in
  subfolders too, as a package. Dashboards are therefore `.yml`. `.md`, `.sh` and dot files are
  not loaded.
- Edit files in `/config/gungors` live.
