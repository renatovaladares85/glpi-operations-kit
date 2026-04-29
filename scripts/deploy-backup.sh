#!/usr/bin/env bash
set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-staging}"
exec bash "$SCRIPT_ROOT/glpictl.sh" "$ENVIRONMENT" deploy apply backup
