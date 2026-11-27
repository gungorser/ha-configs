# mail

Inbound mail for `@gungors.duckdns.org`: **docker-mailserver** (Postfix + Dovecot) with accounts from
**LLDAP**, and **Roundcube** webmail. Built so Sercan can receive verification mails (second Eufy
account); it only receives, it does not send.

| File | What |
|---|---|
| `compose.yaml` | `mailserver` (port 25 published) and `roundcube` (`mail.gungors.duckdns.org`, LAN only through NPM) on the `proxy` network |
| `hook.sh` | `pre`: data folders and `/opt/secrets/mail.env` (LDAP bind password = auth's `sssd` read-only bind user); `post`: waits for port 25 |

## Live target

Docker VM `/opt/stacks/mail`, data in `/srv/data/mail` (`data` mailboxes, `config`, `state`, `logs`,
`roundcube`). Secret: `/opt/secrets/mail.env` (600), never in git.

## Accounts

- Mailbox = LLDAP user in group `cekirdek_aile` (sercan, melike) with the user's `mail` attribute
  (`sercan@gungors.duckdns.org`). IMAP/webmail login: the LLDAP user name (`sercan`) and password.
- The auth area must be deployed first (bind user `sssd`).

## Internet side (not in this repo)

- DNS: `gungors.duckdns.org` has an MX pointing at itself and the A record is the home IP (Duck DNS).
- Router: forward TCP **25** to `192.168.0.222`. Many ISPs block inbound 25; test from outside
  (mobile data: `nc -vz <public ip> 25`) and by mailing the address from another provider.
- No outbound mail, no DKIM/SPF/DMARC, no spam filter (plain inbound; filtering is off to keep it small).

## Deploy

On the Proxmox host as `claude`: `mail/deploy.sh <mode>` (`status`, `deploy`, `force`, `rollback`), then
`proxy/deploy.sh deploy` for the `mail.` proxy host.

## Check

- `mail/deploy.sh status`: containers up, `mail-mailserver-1` healthy.
- On the VM: `sudo docker exec mail-mailserver-1 doveadm user sercan` shows the LDAP user;
  LAN test: `swaks --to sercan@gungors.duckdns.org --server 192.168.0.222` then open webmail.

## Rollback

`mail/deploy.sh rollback` (again to undo). Mailboxes live in `/srv/data/mail` and stay.

## Don't

- Open IMAP or SMTP submission to the internet; only port 25 is published.
- Put the bind password in git.
