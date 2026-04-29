#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${1:-staging}"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook
export_runtime_inventory_if_present "$ENVIRONMENT"
write_step "Deploying backup role for $ENVIRONMENT"
invoke_ansible "$ENVIRONMENT" "backup"
