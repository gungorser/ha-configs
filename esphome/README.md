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
`*.yaml` files, deletes nothing, records the commit in `.ha-configs-deployed`. Installing on a
device is a separate click in the ESPHome UI ("Install"); without it the device keeps its firmware.

## Check
The ESPHome UI shows the devices as valid; after an install, the device is online in HA.

## Rollback
`configs_deploy` with `{"area": "esphome", "mode": "rollback"}` (restores the previous files; the
device keeps whatever was installed).

## Don't
Edit device files in the ESPHome UI: the next deploy stops on them (or overwrites them with `force`).
