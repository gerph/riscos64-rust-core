#!/bin/bash
set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage:
  $0 runs [limit]
  $0 failed-log <run-id>
  $0 release [tag]
EOF
    exit 1
}

command -v gh >/dev/null 2>&1 || {
    echo "gh is required for ci-status.sh" >&2
    exit 1
}

subcommand="${1:-runs}"

case "$subcommand" in
    runs)
        limit="${2:-10}"
        exec gh run list --workflow build.yml --limit "$limit"
        ;;
    failed-log)
        [ "$#" -eq 2 ] || usage
        exec gh run view "$2" --log-failed
        ;;
    release)
        if [ "$#" -eq 2 ]; then
            exec gh release view "$2"
        fi
        exec gh release view
        ;;
    *)
        usage
        ;;
esac
