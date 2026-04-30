#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-check}"
TARGET="${2:-all}"
ENVIRONMENT="${GLPI_ENVIRONMENT:-staging}"
export GLPI_ENVIRONMENT="$ENVIRONMENT"

exec bash "$SCRIPT_ROOT/glpictl.sh" "$ENVIRONMENT" deploy "$MODE" "$TARGET"
