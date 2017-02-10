# proxmox-scripts

Some little helpers for Proxmox Virtual Enviroment

## vzdump_hook.sh

Hook script for Proxmox VZDump utility. It removes or changes disk
throttles before the dump starts and restores the original throttle
after the dump has finished.
