#!/usr/bin/env bash
set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-reload}"
ENVIRONMENT="${2:-${GLPI_ENVIRONMENT:-staging}}"
export GLPI_ENVIRONMENT="$ENVIRONMENT"
exec bash "$SCRIPT_ROOT/glpictl.sh" "$ENVIRONMENT" tls "$ACTION"
