#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ACTION="${1:-reload}"
ENVIRONMENT="${2:-staging}"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
INVENTORY_RUNTIME_PATH="$RUNTIME_DIR/inventory.runtime.yml"
APP_RUNTIME_PATH="$RUNTIME_DIR/app.runtime.yml"

ensure_directory "$RUNTIME_DIR"
ensure_directory_mode "$RUNTIME_DIR" "700"
require_bootstrap_marker
ensure_script_directory_executable "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook ansible-inventory

if [[ ! -f "$INVENTORY_RUNTIME_PATH" || ! -f "$APP_RUNTIME_PATH" ]]; then
  echo "Missing runtime inventory or app runtime data. Run scripts/deploy-staging.sh check first." >&2
  exit 1
fi

domain="$(awk -F'"' '/glpi_domain:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
glpi_version="$(awk -F'"' '/glpi_version:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
local_cert_path=""
local_key_path=""
tls_mode="none"

case "$ACTION" in
  disable)
    tls_mode="none"
    ;;
  self-signed)
    tls_mode="self_signed"
    ;;
  install-provided)
    tls_mode="provided"
    local_cert_path="$(read_existing_file "Local TLS certificate path" "A valid certificate file is required to switch staging to provided TLS mode." "$APP_RUNTIME_PATH")"
    local_key_path="$(read_existing_file "Local TLS private key path" "A valid private key file is required to switch staging to provided TLS mode." "$APP_RUNTIME_PATH")"
    ;;
  reload)
    tls_mode="$(awk -F'"' '/glpi_tls_mode:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
    local_cert_path="$(awk -F'"' '/glpi_tls_provided_local_cert_path:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
    local_key_path="$(awk -F'"' '/glpi_tls_provided_local_key_path:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
    ;;
  *)
    echo "Unsupported TLS action: $ACTION" >&2
    echo "Supported actions: disable, self-signed, install-provided, reload" >&2
    exit 1
    ;;
esac

write_app_runtime "$APP_RUNTIME_PATH" "$glpi_version" "$domain" "$tls_mode" "$domain" "$local_cert_path" "$local_key_path"
export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
invoke_ansible "$ENVIRONMENT" "app" "$APP_RUNTIME_PATH"
echo "TLS action '$ACTION' completed."
