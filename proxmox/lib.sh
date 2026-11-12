#!/bin/bash
# Shared helpers for docker-vm.sh and haos-vm.sh (sourced, not run).
# shellcheck disable=SC2034  # used by the scripts that source this file

STORAGE=local-lvm
BRIDGE=vmbr0
CACHE=/var/lib/vz/import

die() { echo "error: $*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

# Asks before destroying an existing VM; returns when the id is free.
# Disks attached by a /dev path (nas-data, SSD2) are detached first so they are never touched.
free_vmid() {
  local id=$1 name=$2 answer key
  qm status "$id" >/dev/null 2>&1 || return 0
  echo "VM $id already exists:"
  qm config "$id" | grep -E '^(name|memory|net0|scsi[0-9]+|usb[0-9]+):'
  read -r -p "Type 'destroy $name' to stop and delete VM $id and its own disks: " answer
  [ "$answer" = "destroy $name" ] || die "VM $id kept, nothing changed"
  qm stop "$id" >/dev/null 2>&1 || true
  for key in $(qm config "$id" | awk -F': ' '$2 ~ /^\/dev\// {print $1}'); do
    echo "detaching $key (not deleted): $(qm config "$id" | awk -F': ' -v k="$key" '$1 == k {print $2}')"
    qm set "$id" --delete "$key" >/dev/null
  done
  qm destroy "$id" --purge 1
}
