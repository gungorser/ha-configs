#!/bin/sh
# Deploys gungors/ (HA packages + YAML dashboards) to /config/gungors with the shared swap
# (swap.sh). Run by shell_command.configs_deploy / configs_status; see README.md here.
G="git -c safe.directory=/config/.ha-configs.git --git-dir=/config/.ha-configs.git"
$G show master:swap.sh | sh -s -- "${1:-status}" gungors /config/gungors
