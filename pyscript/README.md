# pyscript

Python automations for the HACS integration [pyscript](https://github.com/custom-components/pyscript).
Settings are in `gungors/packages/pyscript.yaml`.

- `<topic>.py`: one file per topic (like packages); shared helpers in `modules/`.

## Live target
`/config/pyscript` (the only folder pyscript reads).

## Deploy
`configs_deploy` with `{"area": "pyscript"}` (shared swap, `../swap.sh`), then `pyscript.reload`
(no restart).

## Check
`ha_get_logs` for pyscript errors; the automations' triggers.

## Rollback
`configs_deploy` with `{"area": "pyscript", "mode": "rollback"}`, then `pyscript.reload`.

## Don't
Edit files in `/config/pyscript` live.
