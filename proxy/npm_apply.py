#!/usr/bin/env python3
"""Applies hosts.toml to Nginx Proxy Manager through its REST API (run by hook.sh on the VM).

  npm_apply.py status   report repo vs NPM, UI edits since the last apply, unmanaged hosts
  npm_apply.py check    exit 1 when NPM was changed in the UI since the last apply
  npm_apply.py deploy   apply; stops (exit 1) on UI edits
  npm_apply.py force    apply even over UI edits (Sercan's approval only)
  npm_apply.py refresh  re-apply only when the home's public IP changed (timer on the VM)

Managed: the access lists in hosts.toml, the wildcard certificate (created if missing) and the
hosts with live = true. Only the fields below are compared and written; anything else set in the
UI (e.g. HSTS) is left alone. Hosts not in hosts.toml are reported, never deleted.
The state of the last apply is kept in /srv/data/proxy/ha-configs-applied.json.
Credentials: /opt/secrets/proxy.env (NPM_API_EMAIL, NPM_API_PASSWORD) and
/opt/secrets/duckdns.env (DUCKDNS_TOKEN); never printed.
"""
import json
import os
import socket
import sys
import time
import tomllib
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = os.environ.get("NPM_API", "http://127.0.0.1:81/api")
STATE = "/srv/data/proxy/ha-configs-applied.json"
SECRETS = "/opt/secrets"
FIELDS = ["forward_scheme", "forward_host", "forward_port", "certificate_id", "ssl_forced",
          "http2_support", "block_exploits", "allow_websocket_upgrade", "access_list_id",
          "advanced_config"]


def env_file(name):
    out = {}
    with open(os.path.join(SECRETS, name)) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    return out


class Npm:
    def __init__(self, email, password):
        self.token = None
        for _ in range(30):  # NPM may still be starting after compose up
            try:
                self.token = self.call("POST", "/tokens", {"identity": email, "secret": password})["token"]
                return
            except OSError as e:  # URLError/HTTPError, connection reset while NPM starts
                if isinstance(e, urllib.error.HTTPError) and e.code in (400, 401, 403):
                    sys.exit("NPM login failed: check NPM_API_EMAIL / NPM_API_PASSWORD in proxy.env")
                time.sleep(2)
        sys.exit(f"NPM API not reachable at {API}")

    def call(self, method, path, body=None):
        req = urllib.request.Request(API + path, method=method,
                                     data=None if body is None else json.dumps(body).encode())
        req.add_header("Content-Type", "application/json")
        if self.token:
            req.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            if self.token is None:
                raise
            sys.exit(f"NPM API {method} {path}: {e.code} {e.read().decode(errors='replace')[:500]}")


def snippet(name):
    """A file of snippets/ without its comment lines."""
    with open(os.path.join(HERE, "snippets", name)) as f:
        return "\n".join(l.rstrip() for l in f if l.strip() and not l.lstrip().startswith("#"))


def acl_allow(cfg, name, wan_ip):
    """An access list's allowed addresses; allow_home_wan adds the home's own public IP, which only
    traffic from inside the house reaches NPM with (the router's NAT loopback rewrites the source)."""
    acl = cfg["access_lists"][name]
    allow = list(acl["allow"])
    if acl.get("allow_home_wan") and wan_ip:
        allow.append(wan_ip)
    return allow


def home_wan(cfg, previous):
    """The home's public IP from DNS (Duck DNS); the last known one when DNS fails."""
    try:
        return socket.gethostbyname(cfg["defaults"]["home_wan_name"])
    except (OSError, KeyError):
        print(f"warning: home public IP not resolved, keeping {previous}")
        return previous


def desired(cfg, lists, cert_id, wan_ip=None):
    """Payload per live domain, with ids resolved; None ids mean 'not created yet'."""
    d = cfg["defaults"]
    out, planned = {}, []
    for h in cfg["host"]:
        if not h.get("live"):
            planned.append(h["domain"])
            continue
        scheme, rest = h["forward"].split("://", 1)
        host, port = rest.rsplit(":", 1)
        adv = []
        if "max_body" in h:
            adv.append(f"client_max_body_size {h['max_body']};")
        if h.get("auth") == "authelia":
            # NPM drops its own `location /` (and with it the access list) when the advanced
            # config has one, so the lan-only and websocket lines are repeated here.
            loc = []
            if h.get("access") == "lan":
                loc += [f"allow {a};" for a in acl_allow(cfg, "lan-only", wan_ip)] + ["deny all;"]
            if h.get("websockets"):
                loc += ["proxy_set_header Upgrade $http_upgrade;",
                        "proxy_set_header Connection $http_connection;", "proxy_http_version 1.1;"]
            loc += [snippet("authelia-location.conf"), "include conf.d/include/proxy.conf;"]
            adv += [snippet("authelia-authz.conf"),
                    "location / {\n" + "\n".join("    " + l for x in loc for l in x.split("\n")) + "\n}"]
        out[h["domain"]] = {
            "forward_scheme": scheme, "forward_host": host, "forward_port": int(port),
            "certificate_id": cert_id, "ssl_forced": d["ssl_forced"], "http2_support": d["http2"],
            "block_exploits": d["block_exploits"],
            "allow_websocket_upgrade": bool(h.get("websockets", False)),
            "access_list_id": lists.get("lan-only") if h.get("access") == "lan" else 0,
            "advanced_config": "\n".join(adv),
        }
    return out, planned


def pick(host):
    return {k: host.get(k) for k in FIELDS}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "status"
    if mode not in ("status", "check", "deploy", "force", "refresh"):
        sys.exit("usage: npm_apply.py status|check|deploy|force|refresh")
    cfg = tomllib.load(open(os.path.join(HERE, "hosts.toml"), "rb"))
    sec = env_file("proxy.env")
    npm = Npm(sec["NPM_API_EMAIL"], sec["NPM_API_PASSWORD"])
    applied = json.load(open(STATE)) if os.path.exists(STATE) else {}
    wan_ip = home_wan(cfg, applied.get("wan_ip"))
    if mode == "refresh" and wan_ip == applied.get("wan_ip"):
        return
    hosts = {dn: h for h in npm.call("GET", "/nginx/proxy-hosts") for dn in h["domain_names"]}
    acls = {a["name"]: a for a in npm.call("GET", "/nginx/access-lists?expand=clients")}
    lists = {n: a["id"] for n, a in acls.items()}

    def acl_clients(name):
        return [{"address": a, "directive": "allow"} for a in acl_allow(cfg, name, wan_ip)] \
            + [{"address": "all", "directive": "deny"}]

    def acl_differs(name):
        have = [(c["address"], c["directive"]) for c in acls[name].get("clients", [])]
        return sorted(have) != sorted((c["address"], c["directive"]) for c in acl_clients(name))
    certs = {",".join(c["domain_names"]): c["id"] for c in npm.call("GET", "/nginx/certificates")}
    cert_name = cfg["defaults"]["certificate"]
    want, planned = desired(cfg, lists, certs.get(cert_name), wan_ip)

    # UI edits: a managed host whose fields changed since the last apply.
    ui_edits = [dn for dn, fields in applied.get("hosts", {}).items()
                if dn in hosts and pick(hosts[dn]) != fields]
    todo = [dn for dn in want if dn not in hosts or pick(hosts[dn]) != want[dn]]
    unmanaged = sorted(dn for dn in hosts if dn not in want)

    for dn in ui_edits:
        changed = {k: (applied["hosts"][dn][k], hosts[dn].get(k)) for k in FIELDS
                   if applied["hosts"][dn][k] != hosts[dn].get(k)}
        print(f"UI edit: {dn}: " + ", ".join(f"{k} {a!r} -> {b!r}" for k, (a, b) in changed.items()))
    if mode in ("status", "check"):
        if cert_name not in certs:
            print(f"missing certificate {cert_name}")
        for name in cfg.get("access_lists", {}):
            if name not in lists:
                print(f"missing access list {name}")
            elif acl_differs(name):
                print(f"access list {name} differs (home public IP now {wan_ip})")
        for dn in todo:
            print(("missing host " if dn not in hosts else "differs from repo: ") + dn)
        if unmanaged:
            print("not in hosts.toml (left alone): " + ", ".join(unmanaged))
        if planned:
            print("planned, not live yet: " + ", ".join(planned))
        if mode == "status" and not (ui_edits or todo):
            print("proxy hosts: in sync")
        sys.exit(1 if mode == "check" and ui_edits else 0)

    if ui_edits and mode in ("deploy", "refresh"):
        sys.exit("Stopped: UI edits above. Merge them into hosts.toml or use force (Sercan only).")
    if mode == "refresh":
        print(f"home public IP changed: {applied.get('wan_ip')} -> {wan_ip}")

    for name in cfg.get("access_lists", {}):
        body = {"name": name, "satisfy_any": True, "pass_auth": False, "items": [],
                "clients": acl_clients(name)}
        if name not in lists:
            lists[name] = npm.call("POST", "/nginx/access-lists", body)["id"]
            print(f"created access list {name}")
        elif acl_differs(name):
            npm.call("PUT", f"/nginx/access-lists/{lists[name]}", body)
            print(f"updated access list {name}")
    if cert_name not in certs:
        dd = env_file("duckdns.env")
        body = {"provider": "letsencrypt", "nice_name": cert_name, "domain_names": [cert_name],
                "meta": {"dns_challenge": True, "dns_provider": "duckdns",
                         "dns_provider_credentials": f"dns_duckdns_token={dd['DUCKDNS_TOKEN']}",
                         "propagation_seconds": 120}}
        print(f"requesting certificate {cert_name} (DNS challenge, ~2-3 min)")
        certs[cert_name] = npm.call("POST", "/nginx/certificates", body)["id"]
        print(f"created certificate {cert_name}")
    want, _ = desired(cfg, lists, certs[cert_name], wan_ip)
    for dn, fields in want.items():
        if dn in hosts and pick(hosts[dn]) == fields:
            continue
        if dn in hosts:
            npm.call("PUT", f"/nginx/proxy-hosts/{hosts[dn]['id']}", fields)
            print(f"updated {dn}")
        else:
            npm.call("POST", "/nginx/proxy-hosts", dict(fields, domain_names=[dn], meta={}, locations=[]))
            print(f"created {dn}")
    hosts = {dn: h for h in npm.call("GET", "/nginx/proxy-hosts") for dn in h["domain_names"]}
    state = {"hosts": {dn: pick(hosts[dn]) for dn in want if dn in hosts}, "wan_ip": wan_ip}
    tmp = STATE + ".new"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, STATE)
    if unmanaged:
        print("not in hosts.toml (left alone): " + ", ".join(unmanaged))
    print(f"proxy hosts applied ({len(want)} live, {len(planned)} planned)")


if __name__ == "__main__":
    main()
