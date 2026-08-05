#!/bin/bash
set -euo pipefail

MODE="${MODE:-backup}"

echo "=================================="
echo "Running in mode: ${MODE}"
echo "=================================="

case "${MODE}" in

  backup)
    exec /scripts/backup.sh
    ;;

  restore)
    exec /scripts/restore.sh
    ;;

  *)
    echo "Invalid MODE: ${MODE}"
    echo "Allowed values: backup | restore"
    exit 1
    ;;

esac
