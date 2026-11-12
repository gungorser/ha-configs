#!/bin/bash
# Deploys the auth area (LLDAP + Authelia) to the docker VM; see README.md here.
# Runs on the Proxmox host as claude. mode: status | deploy | force (Sercan only) | rollback
exec "$(dirname "$0")/../docker-host/stack.sh" auth "${1:-status}"
