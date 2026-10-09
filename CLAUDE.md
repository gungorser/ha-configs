# ha-configs

Home Assistant YAML (checked out on HA at `/config/gungors`) and, by the same session, the cards
in ha-dashboards. No agent for YAML or cards: the main session works here itself. Agent here:
`pyscript` (pyscript automations).

## This repository

- Apply live only after Sercan approved the change. Live apply: read the live file first (others
  may have changed it), write with `ha_write_file` (`gungors/...`), check the config, reload the
  domain or restart, verify the entities. A dashboard that references a new entity goes after its
  package. Follow the Home Assistant MCP best-practice skill before automations, helpers, scripts
  or dashboards.
- A new entity on the 3D floor view: find its position in `dashboards/floorplan.yaml` (old 2D) first.
- `gungors` wrappers drive hidden original entities: dashboards and automations use the wrapper
  (`cover.sercan_cover`, never `cover.sercan_blind`). Options and attributes: ha-integrations README.
- Credentials only via `!secret`. UI-only integrations stay in the UI. UI automations moved into
  packages keep their `id`.
- Page entity ids and the card <-> page protocol: ha-floorplan `src/render/config*.json` and
  `docs/page.md` (read only).
- Cards (ha-dashboards; `add_repo gungorser/ha-dashboards` in a cloud session if it is missing):
  bump `VERSION`, commit, GitHub release `vX.Y.Z`, update in HACS, bump the resource `&v=` so
  browsers load the new card.

## Rules (all Gungor HA repositories)

- Reply to Sercan in Turkish. Commit messages, code comments and repo docs in English.
- Work on a branch, open a PR to the default branch and merge it yourself when it is green and
  conflict-free; no PRs stacked on unmerged branches. Live changes (HA, renders) follow the repo's rules.
- Blender only through the Blender MCP (Sercan's live Blender). Home Assistant only through the
  Home Assistant MCP. Nobody reads or writes `secrets.yaml`; ask Sercan for new secrets.
- Read a repo's README first, then only the doc section you need (`grep -n '^## '`).

## Agents

Each agent lives in the repository it owns (`.claude/agents/`). Clone the repositories side by side
(`../ha-floorplan`, `../ha-configs`, ...); in a cloud session the project repositories already are.
ha-configs (with the ha-dashboards cards) and ha-integrations have no agent: the main session works
there itself, following that repository's CLAUDE.md.

| Agent | Repo | Does | Never |
|---|---|---|---|
| `modeler` | ha-floorplan | Draws the house in Blender: geometry, furniture, where things go; perspective screenshots | Render cameras, renders, deploys, HA |
| `baking` | ha-floorplan | Ortho render cameras, render layers, light effects, the page and UI, renders, deploy | Draws or moves things in the house |
| `pyscript` | ha-configs | pyscript automations in `pyscript/` (placeholder, scope still being defined) | Touches Blender |

- Small work (size, colour, one YAML line, a one-file fix): one session, no agents. Big work
  (something new from scratch, a page/card protocol change): the agent chain. No separate
  verifier: each agent checks its own work before its handoff note. No screenshots or previews
  unless a step needs one or Sercan asks.
- The main session calls the agents in order and passes each handoff note on; agents do not call
  each other. Independent steps may run in parallel (modeler draws while baking renders).
- Blender has no owner: every agent uses it for its own function and never does another agent's.
  The live Blender answers one call at a time, so calls stay short; renders and builds run in a
  background Blender (ha-floorplan `src/render/bake.py`) and never block it.
- Flows: new thing on the 3D view: main session in ha-configs (old 2D position, HA entity) ->
  modeler -> baking -> main session (`floorplan_3d.yaml` mapping). Page/card protocol change:
  baking (page + `docs/page.md`) -> main session (card in ha-dashboards). Integration change:
  ha-integrations (release) -> ha-configs (YAML, `gungors.reload`).
- Contracts (change one side, update the other): Blender object names (modeler -> baking), page
  entity ids and `docs/page.md` (baking -> card), HA entity ids (ha-configs -> all), `gungors`
  options and attributes in the ha-integrations README (ha-integrations -> ha-configs, baking).

Every agent ends with a handoff note:

```
done: <what changed, files, commits/branch>
verified: <how>
next: <agent or main session> - <what it needs to do, ids/names it needs>
open: <anything Sercan must decide>
```
