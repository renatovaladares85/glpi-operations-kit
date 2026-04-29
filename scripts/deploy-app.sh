#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${1:-staging}"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
APP_RUNTIME_PATH="$RUNTIME_DIR/app.runtime.yml"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook
export_runtime_inventory_if_present "$ENVIRONMENT"
write_step "Deploying GLPI application role for $ENVIRONMENT"
if [[ -f "$APP_RUNTIME_PATH" ]]; then
  invoke_ansible "$ENVIRONMENT" "app" "$APP_RUNTIME_PATH"
else
  invoke_ansible "$ENVIRONMENT" "app"
fi
