# auth

Users and login for every service (plan doc section 5): **LLDAP** keeps users and groups,
**Authelia** is the login portal (2FA off for now, see below), gates the admin tools through NPM forward-auth and
will be the OIDC provider for Proxmox, Immich and Paperless.

| File | What |
|---|---|
| `compose.yaml` | `lldap` (`lldap/lldap`, rootless, uid 8001) and `authelia` (`authelia/authelia`, uid 8002), pinned, on the `proxy` network, no published ports |
| `authelia/configuration.yml` | Authelia config, mounted read-only: LLDAP backend, access rules, session, TOTP |
| `lldap-bootstrap/` | Users, groups and the POSIX attribute schema, applied by LLDAP's `bootstrap.sh` |
| `hook.sh` | Generates secrets once, assembles the bootstrap folder, runs it after compose up |
| `lldap-prune.sh` | Removes memberships of listed users that the lists no longer give (run by `hook.sh` post) |

| Group | Members | Access |
|---|---|---|
| `admin` | sercan | everything: Proxmox, paperless-gpt, plus all below; NPM and the LLDAP UI use their own login, LAN only |
| `cekirdek_aile` | sercan, melike | Home Assistant, Paperless, `home.*`, plus Immich |
| `aile` | sercan, melike, halil, insaf, murat, nezahat, onur | Immich; NAS shares `foto`, `dokuman`, `muzik` (people with a NAS account) |
| `misafir` | (empty; a visiting guest gets a user made in the LLDAP UI, e.g. osman) | Home Assistant only (what HA gives the guest) |
| `servis` | ha-media | service accounts: no web/app login (no policy admits them); ha-media reads the NAS shares `muzik`, `floorplan` |
| `lldap_admin` | sercan | manages users in the LLDAP UI |
| `lldap_password_manager` | authelia (service user) | password reset (disabled in Authelia) |

The groups nest (aile < cekirdek_aile < admin): a person is a member of every group up to theirs,
and each policy checks one group. Authelia OIDC policies (`configuration.yml`): `admin` ->
Proxmox; `home_assistant` (cekirdek_aile, misafir) -> both HA clients; `cekirdek_aile` ->
Paperless; `aile` -> Immich.

- Base DN `dc=gungors,dc=duckdns,dc=org`; LDAP at `ldap://lldap:3890` inside Docker (not published
  yet: Samba/SSSD and the Proxmox realm publish it when they come).
- POSIX attributes for later SSSD/Samba: `uidnumber` (users 10001+), `gidnumber` (groups 20000+,
  user's primary group), `homedirectory`, `loginshell`, `sshpublickey` (list, editable).
- `users.json` holds sercan, melike and the service accounts (placeholder e-mails; Immich
  links them by OIDC subject). The relatives and guests are made by Sercan in the LLDAP UI with their real
  e-mail (Immich uses it) and group `aile` (guests: `misafir`); they are not in the repo, because `bootstrap.sh`
  overwrites e-mail, display name and avatar of every listed user. New relative: LLDAP UI ->
  Create user (e-mail, password), then add group `aile`.
- For the listed users the repo is the truth: bootstrap adds users, groups and memberships, then
  `lldap-prune.sh` (hook post) removes memberships the lists no longer give. Users and groups are
  never deleted by a deploy; a user removed from `users.json` is removed in the UI by hand.
- 2FA: off since 2026-11-12 (Sercan's decision); admin rules use `one_factor`. To turn it on,
  set them back to `two_factor`; TOTP stays configured.
- TOTP (when on). Without SMTP, Authelia writes the registration code and reset links to
  `/srv/data/auth/authelia/notification.txt` (read by Claude on request).
- OIDC: provider at `https://auth.gungors.duckdns.org` (discovery:
  `/.well-known/openid-configuration`), signing key and HMAC secret from `/opt/secrets/auth/authelia/`.
  Clients: `homeassistant` (public, PKCE, no secret; redirect `https://ha.*` and
  `https://homeassistant.*` `/auth/oidc/callback`; scopes openid, profile, groups) for HA's
  hass-oidc-auth, which maps group `admin` to HA admins and other groups to users (policy `cekirdek_aile`).
  `paperless` (confidential, PKCE, `client_secret_basic`; secret made once by `hook.sh` into
  `/opt/secrets/oidc/paperless.secret`, its digest into Authelia's secrets folder).
  `immich` (confidential, PKCE, `client_secret_basic`, secret like paperless'; redirects
  `https://foto.*` `/auth/login` and `/user-settings` and the app's `app.immich:///oauth-callback`;
  authorization policy `aile` (admin, cekirdek_aile, aile); scope `immich` carries the claim
  `immich_role`: `admin` for group `admin`, otherwise `user`).
  `proxmox` (confidential, `client_secret_basic`, PKCE not required; redirects
  `https://proxmox.gungors.duckdns.org` and `https://192.168.0.220:8006`; policy `admin`) for the
  Proxmox realm `authelia` (proxmox area, `pve-realm`).
  `homeassistant-openid` (confidential, PKCE, `client_secret_basic`; redirect
  `https://ha.*` `/auth/openid/callback`; policy `cekirdek_aile`) for HA's hass-openid (cavefire, HACS),
  which replaces hass-oidc-auth: the Android app logs in through the external browser instead of a
  device code. It links the HA users with the same username; HA roles stay set in HA. The plain secret
  (`/opt/secrets/oidc/homeassistant-openid.secret`) goes only into HA's config flow (UI-only integration).

### Secrets (generated by `hook.sh` on first deploy; never in git or chat)

| Where | What |
|---|---|
| `/opt/secrets/auth.env` (600 root) | `LLDAP_JWT_SECRET`, `LLDAP_KEY_SEED`, `LLDAP_LDAP_USER_PASS` (LLDAP `admin`, Claude's break-glass) |
| `/opt/secrets/auth/authelia/` (700, uid 8002) | `jwt_secret`, `session_secret`, `storage_key`, `ldap_password` (service user `authelia`), `oidc_hmac_secret`, `oidc_jwks_rs256.pem` |
| `/opt/secrets/auth/bootstrap/` (700, uid 8001) | repo lists + the service user with its password, mounted into LLDAP |

People's passwords (LLDAP only; they are the one password for Authelia, so Immich, HA, Paperless,
Proxmox): set in the LLDAP UI (`users.*`, LAN; a person can change their own there). Authelia's password reset stays off (no SMTP). The NAS (Samba) password is separate
and set with `set-password` (nas area): LLDAP keeps OPAQUE hashes, so the two cannot be synced.

## Live target

`/opt/stacks/auth` on the docker VM (repo files; `.deployed` = commit), data in `/srv/data/auth`
(`lldap/` database, `authelia/` sqlite + notifications), secrets as above.

## Deploy

On the Proxmox host as `claude`: `auth/deploy.sh <mode>` (shared `docker-host/stack.sh`), then
`proxy/deploy.sh deploy` for the hosts `auth` (public) and `users` (LAN only, Authelia gate).
Order matters on a fresh VM: proxy first (it creates the `proxy` network), then auth.

## Check

- `auth/deploy.sh status`: both containers running, LLDAP healthy.
- `curl -s https://auth.gungors.duckdns.org/api/health` from the house: `{"status":"OK"}`.
- A first-factor login against `/api/firstfactor` works (LDAP bind and user search).

## Rollback

`auth/deploy.sh rollback` restores the previous `/opt/stacks/auth` and restarts. Data and secrets
stay. To take the gate off a host, set its `auth = "none"` in `proxy/hosts.toml` and deploy proxy.

## Don't

- Regenerate or edit the secrets by hand: a new `storage_key` makes the Authelia database
  unreadable (2FA registrations lost); a new `LLDAP_KEY_SEED` invalidates every LLDAP password.
- Put forward-auth in front of Home Assistant (breaks the app and webhooks); HA uses OIDC.
- Delete the LLDAP `admin` or `authelia` users.
