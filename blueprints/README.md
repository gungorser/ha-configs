# blueprints

Our own blueprints, used from packages as `path: gungorser/<name>.yaml`.

- `template/`: `roomstate.yaml` (gungors/packages/template.yaml).
- `automation/`: none now (`.gitkeep` keeps the folder for the deploy; light_with_sensor was
  replaced by the gungors `occupancy` feature).

## Live target
`/config/blueprints/automation/gungorser` and `/config/blueprints/template/gungorser`. Other
folders there (Blackymas, homeassistant, ...) are not ours and are never touched.

## Deploy
`configs_deploy` with `{"area": "blueprints"}` (shared swap per domain, `../swap.sh`), then
`automation.reload` / `template.reload`.

## Check
`ha_get_logs`; the automations that use the blueprint are not unavailable.

## Rollback
`configs_deploy` with `{"area": "blueprints", "mode": "rollback"}`, then the reloads.

## Don't
Edit the blueprints in the HA UI or live: the next deploy stops on them.
