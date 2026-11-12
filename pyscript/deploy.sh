#!/bin/sh
# area-target: ha  (configs_status / configs_deploy on HA run only areas with this line)
# Deploys pyscript/ to /config/pyscript (read by the pyscript integration) with the shared swap
# (swap.sh). Run by shell_command.configs_deploy / configs_status; see README.md here.
G="git -c safe.directory=/config/.ha-configs.git --git-dir=/config/.ha-configs.git"
$G show master:swap.sh | sh -s -- "${1:-status}" pyscript /config/pyscript
