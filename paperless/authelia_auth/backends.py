"""Password logins checked against Authelia (and so LLDAP).

Paperless has no LDAP. Phone apps log in with a username and password (/api/token/, or HTTP Basic
on the API) that Paperless checks only against its own user table. This backend asks Authelia's
first-factor endpoint instead, so the LLDAP password works there too. Authelia's regulation
(brute-force ban) applies. Only users that already exist in Paperless and are linked to the
Authelia OIDC provider are accepted: accounts are still created by the first web (OIDC) login, which
also brings the groups. Nothing here stores or logs a password.
"""
import json
import logging
import os
import urllib.error
import urllib.request

from allauth.socialaccount.models import SocialAccount
from django.contrib.auth import get_user_model
from django.contrib.auth.backends import BaseBackend

log = logging.getLogger("paperless.authelia_auth")

URL = os.getenv(
    "PAPERLESS_AUTHELIA_FIRSTFACTOR_URL", "https://auth.gungors.duckdns.org/api/firstfactor"
)
PROVIDER = os.getenv("PAPERLESS_AUTHELIA_PROVIDER", "authelia")


def authelia_accepts(username, password):
    body = json.dumps(
        {"username": username, "password": password, "keepMeLoggedIn": False}
    ).encode()
    req = urllib.request.Request(
        URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status == 200 and json.load(resp).get("status") == "OK"
    except urllib.error.HTTPError as e:
        if e.code != 401:
            log.warning("Authelia first factor answered HTTP %s", e.code)
        return False
    except (OSError, ValueError) as e:
        log.warning("Authelia first factor unreachable: %s", e)
        return False


class AutheliaBackend(BaseBackend):
    def authenticate(self, request, username=None, password=None, **kwargs):
        if not username or not password:
            return None
        User = get_user_model()
        try:
            user = User.objects.get(username=username)
        except User.DoesNotExist:
            return None
        if not user.is_active:
            return None
        if not SocialAccount.objects.filter(user=user, provider=PROVIDER).exists():
            return None
        if authelia_accepts(username, password):
            return user
        log.info("Authelia refused the password for %s", username)
        return None

    def get_user(self, user_id):
        User = get_user_model()
        try:
            return User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None
