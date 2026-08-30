#!/bin/bash

set -euo pipefail

export PBS_REPOSITORY='XXX'
export PBS_PASSWORD_FILE='/opt/proxmox-backup/secret'
export PBS_FINGERPRINT='XXX'

DOCKER_SCRIPT="/opt/proxmox-backup/dcctrl.sh"
VIGIL_KEY="$(cat /opt/proxmox-backup/vigil-secret)"
VIGIL_URL="http://192.168.178.103:5000/api/v1/sessions"

check_in()  { curl -sS -o /dev/null -f --request POST --header "Client-Key: ${VIGIL_KEY}" "${VIGIL_URL}/check-in"  || echo "WARNING: vigil check-in failed, continuing anyway"; }
check_out() { curl -sS -o /dev/null -f --request POST --header "Client-Key: ${VIGIL_KEY}" "${VIGIL_URL}/check-out" || echo "WARNING: vigil check-out failed"; }

check_in

trap '"$DOCKER_SCRIPT" start' EXIT
echo "--- Stopping Docker containers ---"
"$DOCKER_SCRIPT" stop

echo "--- Running proxmox-backup-client ---"
start_ts=$(date +%s)
proxmox-backup-client backup \
    docker-services.pxar:/opt/services \
    --change-detection-mode=metadata
echo "--- Backup took $(( $(date +%s) - start_ts ))s ---"

check_out
echo "--- Backup complete ---"
