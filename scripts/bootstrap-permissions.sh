#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

write_step "Running local permission bootstrap"

if ! ensure_script_directory_executable "$SCRIPT_ROOT"; then
  echo "Script execute permissions are mandatory and unresolved." >&2
  exit 1
fi

if ! ensure_sudo_ready; then
  echo "sudo/root capability is mandatory for bootstrap." >&2
  exit 1
fi

if ! ensure_group_exists_and_membership "$GLPI_OPS_GROUP"; then
  echo "Group membership is mandatory and unresolved." >&2
  exit 1
fi

ensure_directory_mode "$SCRIPT_ROOT/../.runtime" "700"
write_bootstrap_marker

echo "Bootstrap completed."
echo "Next step example: cp config/.env.example config/staging.env && ./scripts/glpictl.sh staging deploy check all"
