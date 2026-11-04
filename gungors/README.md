# gungors (HA packages and YAML dashboards)

## Live target
`/config/gungors`, with two folders:

- `packages/<topic>.yaml`: one package per topic (file name = package name), any domains mixed.
  `configuration.yaml` (not in this repository) loads them with
  `homeassistant: packages: !include_dir_named gungors/packages`. `packages/deploy.yaml` holds the
  deploy shell_commands for all areas (root README).
- `dashboards/<name>.yaml`: YAML dashboards, registered in `packages/dashboards.yaml`
  (`filename: gungors/dashboards/<name>.yaml`; `floorplan` = old 2D, `floorplan_3d`, `program`,
  `unnecessary`).

## Deploy
`configs_deploy` with `{"area": "gungors"}` (shared swap, `../swap.sh`; both folders at once). Then
reload what changed (automation, script, template, ... or `gungors.reload`), or restart for domains
without a reload. Run HA's config check before a restart. Dashboards only need a browser refresh.

## Check
`ha_get_logs`, the changed entities, the dashboards open. `configs_status` shows no live edits.

## Rollback
`configs_deploy` with `{"area": "gungors", "mode": "rollback"}`, then the same reload or restart.

## Don't
- Put anything but packages under `packages/`: `!include_dir_named` loads every `*.yaml` there, in
  subfolders too, as a package.
- Edit files in `/config/gungors` live.
