#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

write_step "Running local permission bootstrap"

bootstrap_failures=0
scripts_status="fail"
sudo_status="fail"
group_status="fail"
runtime_status="fail"
marker_status="not-created"

if ensure_script_directory_executable "$SCRIPT_ROOT"; then
  scripts_status="ok"
else
  echo "Script execute permissions are mandatory and unresolved." >&2
  bootstrap_failures=$((bootstrap_failures + 1))
fi

if ensure_sudo_ready; then
  sudo_status="ok"
else
  echo "sudo/root capability is mandatory for bootstrap." >&2
  bootstrap_failures=$((bootstrap_failures + 1))
fi

if ensure_group_exists_and_membership "$GLPI_OPS_GROUP"; then
  group_status="ok"
else
  echo "Group membership is mandatory and unresolved." >&2
  bootstrap_failures=$((bootstrap_failures + 1))
fi

if ensure_directory_mode "$SCRIPT_ROOT/../.runtime" "700"; then
  runtime_status="ok ($(file_mode_octal "$SCRIPT_ROOT/../.runtime"))"
else
  echo "Runtime directory permissions are mandatory and unresolved." >&2
  bootstrap_failures=$((bootstrap_failures + 1))
fi

if ((bootstrap_failures == 0)); then
  if write_bootstrap_marker && ensure_mode "$(bootstrap_marker_path)" "600"; then
    marker_status="ok ($(file_mode_octal "$(bootstrap_marker_path)"))"
  else
    marker_status="fail"
    echo "Bootstrap marker could not be written with secure permissions." >&2
    bootstrap_failures=$((bootstrap_failures + 1))
  fi
fi

echo
echo "Bootstrap permission summary:"
echo "- script execute permissions: $scripts_status"
echo "- sudo/root capability: $sudo_status"
echo "- operator group '$GLPI_OPS_GROUP': $group_status"
echo "- runtime directory mode: $runtime_status"
echo "- bootstrap marker: $marker_status"

if ((bootstrap_failures > 0)); then
  echo "Bootstrap incomplete: fix the failed mandatory items above and rerun." >&2
  exit 1
fi

echo "Bootstrap completed."
echo "Next step example: cp config/.env.example config/staging.env && ./scripts/glpictl.sh staging deploy check all"
