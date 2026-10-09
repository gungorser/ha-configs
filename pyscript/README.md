# pyscript

Python automations for the HACS integration [pyscript](https://github.com/custom-components/pyscript).
Settings are in `packages/pyscript.yaml`.

- `<topic>.py`: one file per topic (like packages); shared helpers in `modules/`.
- HA only reads `/config/pyscript`, so on HA it is a symlink to `gungors/pyscript` (created once by hand).
- Deploy: write the file to `gungors/pyscript/` with the HA MCP, then call `pyscript.reload` (no restart).
