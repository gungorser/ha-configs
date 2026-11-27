# floorplan

The 3D floor page of [ha-floorplan](https://github.com/gungorser/ha-floorplan) (page, `settings.json`,
model and render layers per floor) on Home Assistant. Its files are built outside this repository
(renders by Blender), so this area only moves them from the NAS into `/config/www`.

Flow: Blender renders on the docker VM, so ha-floorplan's deploy runs there and copies the page and
the floors into `/srv/nas/foto/floorplan` on its own disk (the NAS share `floorplan`, `nas/`), with a
`.version` stamp; then `configs_deploy` with `{"area": "floorplan"}` swaps a copy into place on HA.
No Samba add-on on HA, no Windows machine.

## Live target

`/config/www/gungors_floor` (served at `/local/gungors_floor/`, the floor card's iframe), copied from
HA network storage `floorplan` (usage **share**, `/share/floorplan` or `/share/Floorplan`, server `192.168.0.222`, share
`floorplan`, user `ha-media`, read-only).

## Deploy

1. ha-floorplan's deploy on the docker VM writes `/srv/nas/foto/floorplan` (only the floors it
   changed; the folder keeps a full copy) and `.version`.
2. `configs_deploy` with `{"area": "floorplan"}`: copies `/share/floorplan` into a stage folder, swaps it
   with the target, keeps the old one in `/config/.ha-configs-prev/floorplan`, writes the source's
   `.version` to `<target>/.deployed`. `force` is the same as `deploy` (nobody edits the target live).
3. Reload the browser (or the TV's Fully) to see the new page.

## Check

`configs_status` lists `floorplan` with the deployed and the source version; the floor dashboard shows
the new renders.

## Rollback

`configs_deploy` with `{"area": "floorplan", "mode": "rollback"}` (again to undo).

## Don't

- Write `/config/www/gungors_floor` directly (Samba add-on, `ha_write_file`): the next deploy replaces it.
- Give `ha-media` write access to the share.
