# immich

Immich (photo library) on the docker VM at `https://foto.gungors.duckdns.org`. Photos come from
the phones through the Immich app (backup of chosen albums); the web UI and the app work inside
and outside the house with the same address.

| File | What |
|---|---|
| `compose.yaml` | `immich-server`, `immich-machine-learning`, `immich-database` (Postgres 14 + VectorChord), `immich-redis` (Valkey); Immich's release compose file for v3.3.5, pinned by tag and digest |
| `immich.json` | Server settings (`IMMICH_CONFIG_FILE`): external domain, OAuth, storage template, job concurrency. Settings in the web UI are locked; change them here |
| `hook.sh` | Secrets, the settings file with the OIDC secret, folders, break-glass admin |

- Photos: `/srv/nas/foto/immich` (nas-foto disk; `upload/`, `library/<user>/<year>/<date>/`,
  thumbnails, encoded videos). Root-only (700), so the Samba share `foto` does not reach it: a
  file changed outside Immich would no longer match its database.
- Database, Valkey, model cache: `/srv/data/immich/{postgres,model-cache}` (nas-data; the
  database must be on a local disk).
- Priority (plan doc: HA > services > Immich): all four containers on cores 2-3, `cpu_shares`
  256, `oom_score_adj` 500, memory limits server 2 GB, ML 2 GB, Postgres 1 GB (512 MB is OOM-killed on the first start), Valkey 128 MB;
  job concurrency 1-2. Models unload after 5 idle minutes. The first scan of a full phone can take
  days; photos show at once, faces and smart search follow.
- Web: NPM `foto` host -> `immich-server:2283` (proxy area), public, unlimited body size, no
  forward-auth (the phone app needs the bare API).

### Users: LLDAP through Authelia

- The web login page goes straight to Authelia (`autoLaunch`). OIDC client `immich`, auth area. Only group `aile` may log in. The
  account is created on the first login (e-mail from LLDAP, storage label = username); the
  claim `immich_role` makes LLDAP `admin` members Immich admins.
- Phone app: server `https://foto.gungors.duckdns.org`, then "Authelia ile giriş" (redirect
  `app.immich:///oauth-callback`).
- Break-glass: local admin `admin@gungors.duckdns.org` made by `hook.sh` on a fresh install;
  password only in `/opt/secrets/immich/admin.password` (root). Password login stays enabled for it:
  `https://foto.gungors.duckdns.org/auth/login?autoLaunch=0` shows the form.

### Secrets (never in git or chat)

| File | What | Made by |
|---|---|---|
| `/opt/secrets/immich.env` | `DB_PASSWORD`, `POSTGRES_PASSWORD` | `hook.sh` (once) |
| `/opt/secrets/oidc/immich.secret` (+ digest in Authelia's folder) | OIDC client secret | auth `hook.sh` |
| `/opt/secrets/immich/immich.json` | `immich.json` + the client secret, mounted read-only | `hook.sh` (every deploy) |
| `/opt/secrets/immich/admin.password` | break-glass admin password | `hook.sh` (fresh install) |

## Live target

`/opt/stacks/immich` on the docker VM; data and photos as above.

## Deploy

`immich/deploy.sh <mode>` on the Proxmox host as `claude` (shared `docker-host/stack.sh`).
Deploy `auth` first (it creates the OIDC client secret), then `immich`, then `proxy` (NPM host).
An Immich upgrade: read the release notes (breaking changes), bump both image tags and digests to
the new release's compose file (Postgres and Valkey pins too), deploy.

## Check

- `immich/deploy.sh status`: deployed = master, four containers up, server healthy.
- `https://foto.gungors.duckdns.org` shows "Authelia ile giriş"; sercan lands as admin, melike
  as user, misafir is refused by Authelia.
- After an upload: the file under `/srv/nas/foto/immich/library/<user>/`, jobs finish in
  Administration > Jobs.

## Rollback

`immich/deploy.sh rollback` restores the previous `/opt/stacks/immich`. Photos and the database
are untouched by deploys. Downgrading the image across a database migration does not work: roll
back only within the same Immich version, or restore the database.

## Don't

- Write into `/srv/nas/foto/immich` by hand or share it over SMB.
- Put the database on the NAS shares or a network mount.
- Put forward-auth in front of `foto` (breaks the phone app).
- Edit `/opt/secrets/immich/immich.json`: it is rewritten from `immich.json` on every deploy.
