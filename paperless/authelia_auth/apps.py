"""Adds the Authelia password backend after Paperless' own backends (PAPERLESS_APPS loads this)."""
from django.apps import AppConfig
from django.conf import settings

BACKEND = "authelia_auth.backends.AutheliaBackend"


class AutheliaAuthConfig(AppConfig):
    name = "authelia_auth"
    default_auto_field = "django.db.models.AutoField"

    def ready(self):
        # Paperless has no setting for extra backends; Django reads this list at every login.
        if BACKEND not in settings.AUTHENTICATION_BACKENDS:
            settings.AUTHENTICATION_BACKENDS = [*settings.AUTHENTICATION_BACKENDS, BACKEND]
