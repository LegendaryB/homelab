#!/bin/bash
set -euo pipefail

export PBS_REPOSITORY='XXX'
export PBS_PASSWORD_FILE='/opt/proxmox-backup/secret'
export PBS_FINGERPRINT='XXX'

DOCKER_SCRIPT="/opt/proxmox-backup/dcctrl.sh"

trap '"$DOCKER_SCRIPT" start' EXIT

echo "--- Stopping Docker containers ---"
"$DOCKER_SCRIPT" stop

echo "--- Running proxmox-backup-client ---"
start_ts=$(date +%s)
proxmox-backup-client backup \
    docker-services.pxar:/opt/services \
    --change-detection-mode=metadata
echo "--- Backup took $(( $(date +%s) - start_ts ))s ---"

echo "--- Backup complete ---"
