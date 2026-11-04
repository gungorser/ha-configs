# esphome

ESPHome device YAMLs. CI (`.github/workflows/esphome.yml`) runs `esphome config` on each PR with
dummy secrets, on the ESPHome version of the HA add-on.

| File | Device | HA config entry title |
|---|---|---|
| `banyo-switchbutton.yaml` | ESP32, 2 relays | yemek_pushbutton (crossed on purpose for now) |
| `yemek-switchbutton.yaml` | ESP32, 3 relays | banyo_pushbutton |
| `nspanel.yaml` | NSPanel `nspanelhome` (Blackymas remote package) | nspanel home |
| `slimmelezer.yaml` | P1 reader (ESP8266) | slimmelezer |

## Live target
`/config/esphome`, the fixed folder of the ESPHome Device Builder add-on. It also holds
`secrets.yaml` (never in git; ask Sercan for new secrets), `archive/` and the add-on's own `.git`.

## Deploy
`configs_deploy` with `{"area": "esphome"}` (`deploy.sh` here, not the swap): writes only our
`*.yaml` files, deletes nothing, records the commit in `.ha-configs-deployed`. The device keeps its
firmware until it is installed (next section).

## Install (compile + OTA)
Done by the agent right after the deploy, through the Device Builder's own API (add-on 2026.10+):
`ha_manage_app(slug="5c53de3b_esphome", path="/api/mcp", method="POST", body=<JSON-RPC>)` with
`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"<tool>","arguments":{...}}}`.

1. `list_devices`: every device online; `has_pending_changes` marks the ones to install.
2. `validate_config` `{"configuration": "<file>.yaml"}` on each changed file: must end
   "Configuration is valid!" (this one uses the real `secrets.yaml`, CI only dummy secrets).
3. `install` `{"configuration": "<file>.yaml"}`, one device at a time: returns a compile job and an
   upload job; poll both with `get_job` `{"job_id": ...}` until `status` is `completed` and
   `exit_code` 0 (the first compile after an add-on update downloads the toolchain, ~10 min).
4. `list_devices` again: the device is `online` with `deployed_version` = the add-on version, and
   its HA entities are available. Only then the next device.

OTA uses `!secret ota_password` (in `secrets.yaml`, set by Sercan). Every device has `safe_mode:`
(not implied by `ota` since ESPHome 2024.6; nspanel gets it from its package): a device that fails
to boot several times in a row boots into safe mode and still accepts OTA, so a fix or the previous
YAML (rollback, then install) can be flashed again.
The switchbuttons also have a "Safe Mode Boot" button: pressing it reboots the device into safe
mode (offline in HA, OTA only) to test recovery; an install brings it back (it also leaves safe
mode by itself after 5 minutes).

## Check
`validate_config` passes on every file; after an install, the device is online in HA.
## Rollback
`configs_deploy` with `{"area": "esphome", "mode": "rollback"}` restores the previous files; the
device keeps whatever was installed, so run Install again for a firmware rollback.

## Don't
Edit device files in the ESPHome UI: the next deploy stops on them (or overwrites them with `force`).
