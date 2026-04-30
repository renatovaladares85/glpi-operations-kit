#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${1:-}"
DOMAIN="${2:-}"
ACTION="${3:-}"
TARGET="${4:-all}"
SCOPE="${5:-}"

if [[ -z "$ENVIRONMENT" || -z "$DOMAIN" || -z "$ACTION" ]]; then
  echo "Usage: ./scripts/glpictl.sh <staging|production> <deploy|certify|promote|tls|ops|audit> <action> [target] [scope]" >&2
  exit 1
fi

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Unsupported environment: $ENVIRONMENT (expected staging|production)" >&2
  exit 1
fi

RUNTIME_DIR="$(runtime_env_dir "$ENVIRONMENT")"
INVENTORY_RUNTIME_PATH="$(runtime_inventory_path "$ENVIRONMENT")"
PUBLIC_RUNTIME_PATH="$(runtime_public_path "$ENVIRONMENT")"
OVERRIDE_RUNTIME_PATH="$(runtime_override_path "$ENVIRONMENT")"
SECRET_PATH="$(runtime_secret_path "$ENVIRONMENT")"
CONFIG_PATH="$(config_file_path "$ENVIRONMENT")"
PROMOTION_GATE_PATH="$SCRIPT_ROOT/../.runtime/promotion/staging-certified.yml"

ensure_runtime_foundation "$ENVIRONMENT"
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" bash git python3 ansible-playbook ansible-inventory

ensure_runtime_inputs_if_missing() {
  require_runtime_file "$CONFIG_PATH" "product configuration file"
  materialize_runtime_from_config "$ENVIRONMENT"
  ensure_runtime_override_file "$ENVIRONMENT"
  ensure_secret_keys "$ENVIRONMENT"
  local ssh_key_path
  ssh_key_path="$(read_product_config_value "$ENVIRONMENT" "network.ssh.private_key_path" || true)"
  if [[ -n "${ssh_key_path// }" ]]; then
    ssh_key_path="$(expand_home_path "$ssh_key_path")"
    enforce_ssh_private_key_permissions "$ssh_key_path"
  fi
}

run_deploy() {
  local mode="$1"
  local target="$2"
  if [[ "$ENVIRONMENT" == "production" && "$mode" != "check" ]]; then
    if [[ ! -f "$PROMOTION_GATE_PATH" ]]; then
      echo "Production blocked. Missing promotion gate file: $PROMOTION_GATE_PATH" >&2
      exit 1
    fi
  fi

  ensure_runtime_inputs_if_missing
  export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"

  if [[ "$mode" == "check" ]]; then
    ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
    echo "Check completed successfully."
    return 0
  fi

  local tags=""
  local extra_var_files=("$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH")
  case "$target" in
    base) tags="base" ;;
    app) tags="app" ;;
    db) tags="db" ;;
    monitoring) tags="monitoring" ;;
    backup) tags="backup" ;;
    all) tags="base,app,db,monitoring,backup" ;;
    *) echo "Unsupported deploy target: $target" >&2; exit 1 ;;
  esac

  case "$mode" in
    apply) invoke_ansible "$ENVIRONMENT" "$tags" "${extra_var_files[@]}" ;;
    post-check) invoke_ansible "$ENVIRONMENT" "app,db" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH" ;;
    *) echo "Unsupported deploy action: $mode (expected check|apply|post-check)" >&2; exit 1 ;;
  esac
}

run_certify() {
  if [[ "$ENVIRONMENT" != "staging" ]]; then
    echo "Certification is only supported for staging." >&2
    exit 1
  fi
  bash "$SCRIPT_ROOT/certify-staging.sh"
}

run_tls() {
  local tls_action="$ACTION"
  local domain local_cert_path local_key_path tls_mode
  ensure_runtime_inputs_if_missing
  domain="$(awk -F'"' '/glpi_domain:/ {print $2}' "$PUBLIC_RUNTIME_PATH" | head -n1)"
  local_cert_path=""
  local_key_path=""
  tls_mode="none"
  case "$tls_action" in
    disable) tls_mode="none" ;;
    self-signed) tls_mode="self_signed" ;;
    install-provided)
      tls_mode="provided"
      local_cert_path="$(read_existing_file "Local TLS certificate path" "Provided mode requires a valid local certificate file." "$OVERRIDE_RUNTIME_PATH")"
      local_key_path="$(read_existing_file "Local TLS private key path" "Provided mode requires a valid local private key file." "$OVERRIDE_RUNTIME_PATH")"
      ;;
    reload)
      tls_mode="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_mode" || true)"
      [[ -z "${tls_mode// }" ]] && tls_mode="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_mode" || true)"
      local_cert_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" || true)"
      [[ -z "${local_cert_path// }" ]] && local_cert_path="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" || true)"
      local_key_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_key_path" || true)"
      [[ -z "${local_key_path// }" ]] && local_key_path="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_provided_local_key_path" || true)"
      ;;
    *)
      echo "Unsupported TLS action: $tls_action (expected disable|self-signed|install-provided|reload)" >&2
      exit 1
      ;;
  esac
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_mode" "$tls_mode"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_use_tls" "$([[ "$tls_mode" == "none" ]] && echo false || echo true)"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_common_name" "$domain"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" "$local_cert_path"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_key_path" "$local_key_path"
  export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
  invoke_ansible "$ENVIRONMENT" "app" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH"
  echo "TLS action '$tls_action' completed."
}

run_ops() {
  if [[ "$ACTION" == "users" ]]; then
    local users_action="$TARGET"
    local users_scope="${SCOPE:-os}"
    bash "$SCRIPT_ROOT/ops-maintenance.sh" users "$ENVIRONMENT" "$users_action" "$users_scope"
    return
  fi
  if [[ "$ACTION" == "cert" ]]; then
    bash "$SCRIPT_ROOT/ops-maintenance.sh" cert "$ENVIRONMENT" "$TARGET"
    return
  fi
  if [[ "$ACTION" == "audit" ]]; then
    bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
    return
  fi
  if [[ "$ACTION" == "resume" ]]; then
    bash "$SCRIPT_ROOT/ops-maintenance.sh" resume "$ENVIRONMENT"
    return
  fi
  echo "Unsupported ops action: $ACTION (expected users|cert|audit|resume)" >&2
  exit 1
}

run_audit() {
  bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
}

run_promote() {
  if [[ "$ENVIRONMENT" != "production" ]]; then
    echo "Promote domain applies to production environment only." >&2
    exit 1
  fi
  if [[ ! -f "$PROMOTION_GATE_PATH" ]]; then
    echo "Missing promotion gate: $PROMOTION_GATE_PATH" >&2
    exit 1
  fi
  run_deploy apply "$TARGET"
}

case "$DOMAIN" in
  deploy) run_deploy "$ACTION" "$TARGET" ;;
  certify) run_certify ;;
  promote) run_promote ;;
  tls) run_tls ;;
  ops) run_ops ;;
  audit) run_audit ;;
  *)
    echo "Unsupported domain: $DOMAIN (expected deploy|certify|promote|tls|ops|audit)" >&2
    exit 1
    ;;
esac
