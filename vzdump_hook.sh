#!/bin/bash
#
# Proxmox VZDump hook script for unthrottleing backups.
#
# Author: RobHost 2016
# License: MIT
# Version: 0.1, reldate 2016-08-30
# Repo: https://github.com/robhost/proxmox-scripts
#
# This script is intended to be used as a hook script for the Proxmox
# VZDump utility. It removes disk throttles before the dump starts and
# restores them after the dump has finished.
# 
# In order to use it, use the configuration directive "script" of the
# vzdump utility. This can be done for scheduled backups by putting
# "script: /path/to/this/script" in /etc/vzdump.conf. Don't forget to
# set executable permission for the script file.
# 
# This script has been tested and used on Proxmox 4.2.


# Find config directives of throttled storage for the VM with the given
# vmid. Echoes a line with spaces removed for each found directive.

_get_throttled_storage() {
  local vmid="$1"

  while read -r cid opts
  do
    [[ "$cid" =~ ^(ide|sata|scsi|virtio)[0-9]+ ]] || continue
    [[ "$opts" =~ (iops|mbps) ]] || continue
    echo "${cid}$opts"
  done < <(qm config "$vmid" -current)
}

# Remove throttleing options in the given storage config string. This
# can be a multiline string with a storage config directive per line
# with spaces removed, as retuned by _get_throttled_storage.
# Echoes in the same format with throttling options removed.

_remove_throttle() {
  local storage="$1"

  for storage in $storage
  do
    local -a storage_a=(${storage/:/ })
    local sid=${storage_a[0]}
    local -a sopts_a=(${storage_a[1]//,/ })

    for i in ${!sopts_a[@]}
    do
      [[ "${sopts_a[$i]}" =~ ^(iops|mbps) ]] || continue
      unset sopts_a[$i]
    done

    local sopts="${sopts_a[*]}" 
    echo "$sid:${sopts// /,}"
  done
}

# Run qm set for the given vmid. All further arguments are handled as
# configuration directives in the format <directive>:<opts> as given by
# _get_throttled_storage and _remove_throttle. VM locks are skipped.
# Echoes the output of qm set.

_update_config() {
  local vmid=$1
  local conf_a=("${@:2}")
  local opts=""

  for conf in "${conf_a[@]}"
  do
    opts+="-${conf/:/ } "
  done

  qm set "$vmid" -skiplock 1 $opts
}

# Remove and restore storage throttles for a VM. First argument is the
# action to do (remove or restore). Secoand argument is the vmid.
# Returns 1 if invalid action.

storage_throttle() {
  local action=$1
  local vmid=$2
  local script_name=$(basename $0)

  # Store config in a persistent location, so it is not lost is case of
  # an unexpected reboot of the host.
  local storageconfpath="/var/tmp/${script_name}/storageconf_${vmid}"

  case "$action" in
    remove)
      local storage=$(_get_throttled_storage "$vmid")

      [[ -n "$storage" ]] || return 0

      mkdir -p "$(dirname "$storageconfpath")"
      echo "$storage" > "$storageconfpath"
      storage=$(_remove_throttle "$storage")
      _update_config "$vmid" $storage
      ;;
    restore)
      [[ -e "$storageconfpath" ]] || return 0

      local storage="$(< "$storageconfpath")"
      _update_config "$vmid" $storage
      rm -f "$storageconfpath"
      ;;
    *)
      echo "invalid action '$action'"
      return 1
      ;;
  esac
}

# Process arguments and environment variables as received from and set
# by vzdump. Output of commands is not redirected.

vzdump_hook() {
  local phase="$1" # (job|backup)-(start|end|abort)/log-end/pre-(stop|restart)/post-restart
  local dumpdir="$DUMPDIR"
  local storeid="$STOREID"

  case "$phase" in
    # set variables for the phases
    job-start|job-end|job-abort)
      ;;&
    backup-start|backup-end|backup-abort|log-end|pre-stop|pre-restart|post-restart)
      local mode="$2" # stop/suspend/snapshot
      local vmid="$3"
      local vmtype="$VMTYPE" # openvz/qemu
      local hostname="$HOSTNAME"
      ;;&
    backup-end)
      local tarfile="$TARFILE"
      ;;&
    log-end)
      local logfile="$LOGFILE" 
      ;;&

    # do work
    job-start)
      ;;
    job-end)
      ;;
    job-abort)
      ;;
    backup-start)
      storage_throttle remove "$vmid"
      ;;
    backup-end)
      storage_throttle restore "$vmid"
      ;;
    backup-abort)
      storage_throttle restore "$vmid"
      ;;
    log-end)
      ;;
    pre-stop)
      ;;
    pre-restart)
      ;;
    post-restart)
      ;;
    *)
      echo "unknown phase '$phase'"
      return 1
      ;;
  esac
}


# If this script is executed, run main function with the given
# command line arguments. Otherwise do nothing. This makes it possible
# to source this script for testing purposes or use of the functions
# from other hook scripts.
[[ "$BASH_SOURCE" != "$0" ]] || vzdump_hook "$@"
