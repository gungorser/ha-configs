# pyscript

Python automations for the HACS integration [pyscript](https://github.com/custom-components/pyscript).
Settings are in `packages/pyscript.yaml`.

- `<topic>.py`: one file per topic (like packages); shared helpers in `modules/`.
- HA only reads `/config/pyscript`, so on HA it is a symlink to `gungors/pyscript` (created once by hand).
- Deploy: merge to master, `shell_command.gungors_git_pull` (see `CLAUDE.md`), then `pyscript.reload` (no restart).
