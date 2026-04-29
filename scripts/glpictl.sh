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
APP_RUNTIME_PATH="$(runtime_app_path "$ENVIRONMENT")"
DB_SECRET_PATH="$(runtime_db_secret_path "$ENVIRONMENT")"
MONITORING_SECRET_PATH="$(runtime_monitoring_secret_path "$ENVIRONMENT")"
PROMOTION_GATE_PATH="$SCRIPT_ROOT/../.runtime/promotion/staging-certified.yml"

ensure_runtime_foundation "$ENVIRONMENT"
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook ansible-inventory

collect_runtime_inputs() {
  local app_host db_host ssh_user ssh_key glpi_version tls_mode tls_common_name local_cert_path local_key_path
  local db_name db_user db_password db_root_password exporter_user exporter_password

  app_host="$(read_hostname_or_ip "${ENVIRONMENT^} app server IP or hostname" "Runtime inventory must target the real application host." "$INVENTORY_RUNTIME_PATH")"
  db_host="$(read_hostname_or_ip "${ENVIRONMENT^} database server IP or hostname" "Runtime inventory must target the real database host." "$INVENTORY_RUNTIME_PATH")"
  ssh_user="$(read_required_value "SSH username" "Ansible needs a real SSH user for remote access." "$INVENTORY_RUNTIME_PATH")"
  ssh_key="$(read_existing_private_key_file "SSH private key path" "Ansible must use a valid private key file for authentication." "$INVENTORY_RUNTIME_PATH")"
  glpi_version="$(read_required_value "Final GLPI version" "Deployment must use an explicit GLPI release version." "$APP_RUNTIME_PATH")"
  tls_mode="$(read_choice "TLS mode" "A clear HTTP/TLS behavior is required." "$APP_RUNTIME_PATH" none self_signed provided)"
  tls_common_name="$app_host"
  local_cert_path=""
  local_key_path=""

  if [[ "$tls_mode" == "provided" ]]; then
    local_cert_path="$(read_existing_file "Local TLS certificate path" "Provided mode requires a valid local certificate file." "$APP_RUNTIME_PATH")"
    local_key_path="$(read_existing_file "Local TLS private key path" "Provided mode requires a valid local private key file." "$APP_RUNTIME_PATH")"
  fi

  db_name="$(read_required_value "GLPI database name" "MariaDB must create or target the application schema." "$DB_SECRET_PATH")"
  db_user="$(read_required_value "GLPI database username" "The application needs a dedicated database user." "$DB_SECRET_PATH")"
  db_password="$(read_required_value "GLPI database password" "Dedicated database user requires password." "$DB_SECRET_PATH" true)"
  db_root_password="$(read_required_value "MariaDB root password" "Ansible must secure MariaDB and create GLPI schema." "$DB_SECRET_PATH" true)"
  exporter_user="$(read_required_value "mysqld_exporter username" "MariaDB exporter needs a dedicated least-privilege account." "$MONITORING_SECRET_PATH")"
  exporter_password="$(read_required_value "mysqld_exporter password" "MariaDB exporter account must authenticate locally." "$MONITORING_SECRET_PATH" true)"

  if [[ "$ENVIRONMENT" == "staging" ]]; then
    write_runtime_inventory "$INVENTORY_RUNTIME_PATH" "$ENVIRONMENT" "$ssh_user" "$ssh_key" "$app_host" "$db_host"
  else
    cat >"$INVENTORY_RUNTIME_PATH" <<EOF
---
all:
  vars:
    ansible_user: ${ssh_user}
    ansible_ssh_private_key_file: ${ssh_key}
    environment_name: ${ENVIRONMENT}
  children:
    glpi_app:
      hosts:
        prd-app:
          ansible_host: ${app_host}
    glpi_db:
      hosts:
        prd-db:
          ansible_host: ${db_host}
EOF
  fi

  write_app_runtime "$APP_RUNTIME_PATH" "$glpi_version" "$app_host" "$tls_mode" "$tls_common_name" "$local_cert_path" "$local_key_path"
  save_yaml_map "$DB_SECRET_PATH" \
    glpi_db_name "$db_name" \
    glpi_db_user "$db_user" \
    glpi_db_password "$db_password" \
    glpi_db_root_password "$db_root_password" \
    glpi_db_app_access_host "$app_host"
  save_yaml_map "$MONITORING_SECRET_PATH" \
    mysqld_exporter_user "$exporter_user" \
    mysqld_exporter_password "$exporter_password" \
    glpi_db_root_password "$db_root_password"
}

ensure_runtime_inputs_if_missing() {
  if [[ -f "$INVENTORY_RUNTIME_PATH" && -f "$APP_RUNTIME_PATH" && -f "$DB_SECRET_PATH" && -f "$MONITORING_SECRET_PATH" ]]; then
    return 0
  fi
  write_step "Runtime files missing for '$ENVIRONMENT'. Collecting inputs now."
  collect_runtime_inputs
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
  local extra_var_files=("$APP_RUNTIME_PATH")
  case "$target" in
    base) tags="base" ;;
    app) tags="app" ;;
    db) tags="db"; extra_var_files+=("$DB_SECRET_PATH") ;;
    monitoring) tags="monitoring"; extra_var_files+=("$MONITORING_SECRET_PATH" "$DB_SECRET_PATH") ;;
    backup) tags="backup" ;;
    all) tags="base,app,db,monitoring,backup"; extra_var_files+=("$DB_SECRET_PATH" "$MONITORING_SECRET_PATH") ;;
    *) echo "Unsupported deploy target: $target" >&2; exit 1 ;;
  esac

  case "$mode" in
    apply) invoke_ansible "$ENVIRONMENT" "$tags" "${extra_var_files[@]}" ;;
    post-check) invoke_ansible "$ENVIRONMENT" "app,db" "$APP_RUNTIME_PATH" "$DB_SECRET_PATH" ;;
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
  local domain glpi_version local_cert_path local_key_path tls_mode
  ensure_runtime_inputs_if_missing
  domain="$(awk -F'"' '/glpi_domain:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
  glpi_version="$(awk -F'"' '/glpi_version:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
  local_cert_path=""
  local_key_path=""
  tls_mode="none"
  case "$tls_action" in
    disable) tls_mode="none" ;;
    self-signed) tls_mode="self_signed" ;;
    install-provided)
      tls_mode="provided"
      local_cert_path="$(read_existing_file "Local TLS certificate path" "Provided mode requires a valid local certificate file." "$APP_RUNTIME_PATH")"
      local_key_path="$(read_existing_file "Local TLS private key path" "Provided mode requires a valid local private key file." "$APP_RUNTIME_PATH")"
      ;;
    reload)
      tls_mode="$(awk -F'"' '/glpi_tls_mode:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
      local_cert_path="$(awk -F'"' '/glpi_tls_provided_local_cert_path:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
      local_key_path="$(awk -F'"' '/glpi_tls_provided_local_key_path:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
      ;;
    *)
      echo "Unsupported TLS action: $tls_action (expected disable|self-signed|install-provided|reload)" >&2
      exit 1
      ;;
  esac
  write_app_runtime "$APP_RUNTIME_PATH" "$glpi_version" "$domain" "$tls_mode" "$domain" "$local_cert_path" "$local_key_path"
  export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
  invoke_ansible "$ENVIRONMENT" "app" "$APP_RUNTIME_PATH"
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
