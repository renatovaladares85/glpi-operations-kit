#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-check}"
TARGET="${2:-all}"

exec bash "$SCRIPT_ROOT/glpictl.sh" production deploy "$MODE" "$TARGET"
