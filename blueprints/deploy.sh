#!/bin/sh
# area-target: ha  (configs_status / configs_deploy on HA run only areas with this line)
# Deploys our blueprints to the gungorser/ folders HA reads them from, with the shared swap
# (swap.sh), one swap per blueprint domain. Run by shell_command.configs_deploy / configs_status;
# see README.md here.
G="git -c safe.directory=/config/.ha-configs.git --git-dir=/config/.ha-configs.git"
RC=0
for d in automation template; do
  $G show master:swap.sh | sh -s -- "${1:-status}" "blueprints/$d" "/config/blueprints/$d/gungorser" || RC=1
done
exit $RC
