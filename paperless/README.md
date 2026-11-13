# paperless

Paperless-ngx on the docker VM, replacing the Pi's HA add-on (`ffbb73c4_paperless`), plus
paperless-gpt (AI tags and OCR with Gemini). The add-on `paperless-mcp` is not carried over.

| File | What |
|---|---|
| `compose.yaml` | `paperless` (pinned 3.4.2; the add-on's 2.20.15 data was imported first, then upgraded), `db` (Postgres), `broker` (Redis), `paperless-gpt` (profile `gpt`) |
| `hook.sh` | Secrets, folders, Paperless groups; `share-all` after an import |

- Data: `/srv/data/paperless/{data,pgdata,redis,gpt}` (nas-data). Documents:
  `/srv/nas/dokuman/paperless/{media,consume,export}` (nas-dokuman). Consume folder recursive,
  polled every 60 s, duplicates rejected, an archive PDF always kept (as on the add-on), filename format `{{ created_year }}/{{ correspondent }}/{{ title }}`, OCR
  `nld+eng+tur` (as on the add-on). No Tika/Gotenberg (the add-on had none).
- Web: `https://paperless.gungors.duckdns.org` through NPM (`paperless:8000` on the `proxy`
  network), no forward-auth: apps use API tokens.

### Users: LLDAP through Authelia

- The login page goes straight to Authelia (`PAPERLESS_REDIRECT_LOGIN_TO_SSO`; OIDC client `paperless`, confidential, PKCE). The account is
  created on the first login with the LLDAP username; LLDAP groups `admin` and `aile` are synced
  into the Paperless groups of the same name, which `hook.sh` keeps: `admin` has every permission,
  `aile` every document permission (no users/groups admin).
- No Paperless passwords for people. The imported local admin `gungorspapers` stays as the
  break-glass login (regular login stays enabled for it at
  `/accounts/login/?loggedout=1`; its password is Sercan's).
- Ownership: imported objects belong to `gungorspapers`. After the import `hook.sh share-all`
  makes documents, tags, correspondents, types and storage paths unowned (custom fields have no owner), so every
  user with the group permissions sees them (simpler than per-object permissions; new documents
  from the consume folder are unowned anyway).
- Phone apps: create an API token in the web UI (profile) and use it in the app.

### Secrets (never in git or chat)

| File | What | Made by |
|---|---|---|
| `/opt/secrets/paperless.env` | `PAPERLESS_SECRET_KEY`, `POSTGRES_PASSWORD`/`PAPERLESS_DBPASS`, `PAPERLESS_SOCIALACCOUNT_PROVIDERS` (OIDC JSON with the client secret) | `hook.sh` |
| `/opt/secrets/oidc/paperless.secret` (+ digest in Authelia's folder) | OIDC client secret | auth `hook.sh` |
| `/opt/secrets/paperless-gpt.env` | `PAPERLESS_API_TOKEN` (Paperless user `paperless-gpt`, group `aile`, no password), `GOOGLEAI_API_KEY` | token: Claude; Gemini key: Sercan (`set-gemini-key`) |

## Live target

`/opt/stacks/paperless` on the docker VM; data and documents as above.

## Deploy

`paperless/deploy.sh <mode>` on the Proxmox host as `claude` (shared `docker-host/stack.sh`).
Deploy `auth` first (it creates the OIDC client secret). paperless-gpt runs through the
profile `gpt`, enabled in `.env` (`COMPOSE_PROFILES=gpt`); its prompts, workflows, db and UI settings
live in `/srv/data/paperless/gpt/`.

### Migration from the Pi add-on (one time)

1. Copy the add-on's SQLite data dir and `/share/paperless/media` to the VM (add-on stopped
   briefly, Sercan's OK).
2. On the VM, a throwaway `paperless-ngx:2.20.15` container on that copy runs
   `document_exporter` into `/srv/nas/dokuman/paperless/export`.
3. `document_importer` into this stack (same version), then `hook.sh share-all`; compare document,
   tag and correspondent counts with the add-on. The importer runs no workflows, so no Gemini calls.
4. Upgrade the image pin, deploy, check. NPM `paperless` host -> `paperless:8000` (proxy area).
5. paperless-gpt: copy its prompts and workflows from the add-on, new API token, start profile `gpt`.
6. Stop the Pi add-ons (Sercan's OK).

## Check

- `paperless/deploy.sh status`: deployed = master, containers up, `paperless` healthy.
- The login page shows "Authelia"; an LLDAP user lands in Paperless with its groups.

## Rollback

`paperless/deploy.sh rollback` restores the previous `/opt/stacks/paperless`. Before the cutover
the Pi add-on is untouched; after it, point the NPM host back at `192.168.0.221:8000`.

## Don't

- Put forward-auth in front of Paperless (breaks the apps' API tokens).
- Run `document_importer` into a database that already has documents.
- Change `PAPERLESS_SECRET_KEY`; never edit the env files by hand except the Gemini key.
