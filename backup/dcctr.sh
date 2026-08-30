#!/bin/bash

set -euo pipefail
SERVICES_DIR="/opt/services"

usage() {
    echo "Usage: $0 {start|stop}"
    exit 1
}
[ $# -eq 1 ] || usage
ACTION="$1"
[[ "$ACTION" == "start" || "$ACTION" == "stop" ]] || usage

echo "--- Docker Compose stack manager ($ACTION) ---"

find_compose_file() {
    local dir="$1"
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$dir/$f" ]; then
            echo "$dir/$f"
            return 0
        fi
    done
    return 1
}

for dir in "$SERVICES_DIR"/*/; do
    [ -d "$dir" ] || continue
    compose_file=$(find_compose_file "$dir") || {
        echo "[SKIP] $dir → no compose file"
        continue
    }
    echo "[STACK] $(basename "$dir") ($(basename "$compose_file"))"
    case "$ACTION" in
        stop)  echo " → Stopping"; docker compose -f "$compose_file" stop ;;
        start) echo " → Starting"; docker compose -f "$compose_file" start ;;
    esac
done
echo "--- Done ($ACTION) ---"
