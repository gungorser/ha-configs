#!/bin/bash
# Deploys the immich area to the docker VM; see README.md here.
# Runs on the Proxmox host as claude. mode: status | deploy | force (Sercan only) | rollback
exec "$(dirname "$0")/../docker-host/stack.sh" immich "${1:-status}"
