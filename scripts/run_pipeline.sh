#!/usr/bin/env bash
set -euo pipefail

echo "========================================"
echo "Knee MRI Docker pipeline"
echo "========================================"

if [[ "${1:-}" == "--check" ]]; then
    exec "$(dirname "$0")/validate_installation.sh"
fi

echo
echo "MRtrix installation:"
mrinfo -version

if [[ $# -eq 0 ]]; then
    echo
    echo "Container started successfully."
    echo "No processing command was supplied."
    exit 0
fi

echo
echo "Running command:"
printf '%q ' "$@"
echo

exec "$@"
