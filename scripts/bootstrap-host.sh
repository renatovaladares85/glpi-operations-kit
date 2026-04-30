#!/usr/bin/env bash
set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-${GLPI_ENVIRONMENT:-staging}}"
export GLPI_ENVIRONMENT="$ENVIRONMENT"
exec bash "$SCRIPT_ROOT/glpictl.sh" "$ENVIRONMENT" deploy apply base
