# gungors (HA packages and YAML dashboards)

## Live target
`/config/gungors`, with two folders:

- `packages/<domain>.yaml`: one package per Home Assistant domain (file name = package name =
  the only top-level key: `light.yaml` holds `light:`), one commented section per topic inside.
  One exception: `nspanel.yaml` keeps the NSPanel configuration (its blueprint automation) on its
  own; it is a special case, the rule holds for everything else.
  `configuration.yaml` (not in this repository) loads them with
  `homeassistant: packages: !include_dir_named gungors/packages`. `packages/shell_command.yaml` holds the
  deploy shell_commands for all areas (root README).
- `dashboards/<name>.yaml`: YAML dashboards, registered in `packages/lovelace.yaml`
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

## Login (HA side)

- Authelia login is hass-openid (HACS `cavefire/hass-openid`, domain `openid`), configured in the UI
  (Settings > Devices & services > OpenID, discovery `https://auth.gungors.duckdns.org/.well-known/openid-configuration`,
  client `homeassistant-openid`, username field `preferred_username`, create users off, block other
  login methods off). It links `sercan`/`melike` by username. The Android app opens the external
  browser for Authelia, then returns to the app; HA's own username/password login stays as break-glass.
- It replaced hass-oidc-auth (`packages/auth_oidc.yaml`, removed): both patch HA's `/auth/authorize` and
  `/auth/login_flow`, so only one may be active. Rollback: restore `packages/auth_oidc.yaml` from git
  (`git show <commit>^:gungors/packages/auth_oidc.yaml`), delete the OpenID config entry, remove
  hass-openid in HACS, deploy gungors, restart HA.
- hass-openid 1.4.0 breaks on HA 2026.11 (issue #97, PKCE code challenge not passed on); do not update
  HA past 2026.10 until a fixed release (PR #91/#98) is out.
