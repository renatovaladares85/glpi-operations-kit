#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

MODE="${1:-check}"
TARGET="${2:-all}"
ENVIRONMENT="staging"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
INVENTORY_RUNTIME_PATH="$RUNTIME_DIR/inventory.runtime.yml"
APP_RUNTIME_PATH="$RUNTIME_DIR/app.runtime.yml"
DB_SECRET_PATH="$RUNTIME_DIR/db.secrets.yml"
MONITORING_SECRET_PATH="$RUNTIME_DIR/monitoring.secrets.yml"

ensure_directory "$RUNTIME_DIR"
write_step "Preparing execution for environment '$ENVIRONMENT'"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook ansible-inventory

collect_runtime_inputs() {
  local app_host db_host ssh_user ssh_key glpi_version tls_mode tls_common_name local_cert_path local_key_path
  local db_name db_user db_password db_root_password exporter_user exporter_password

  app_host="$(read_hostname_or_ip "Staging app server IP or hostname" "The runtime inventory must target the real application host." "$INVENTORY_RUNTIME_PATH")"
  db_host="$(read_hostname_or_ip "Staging database server IP or hostname" "The runtime inventory must target the real database host." "$INVENTORY_RUNTIME_PATH")"
  ssh_user="$(read_required_value "SSH username" "Ansible needs a real SSH user for remote access." "$INVENTORY_RUNTIME_PATH")"
  ssh_key="$(read_existing_file "SSH private key path" "Ansible must use a valid private key file for authentication." "$INVENTORY_RUNTIME_PATH")"
  glpi_version="$(read_required_value "Final GLPI version" "The deployment must use an explicit GLPI release version." "$APP_RUNTIME_PATH")"
  tls_mode="$(read_choice "TLS mode" "The staging app needs a clear HTTP/TLS behavior." "$APP_RUNTIME_PATH" none self_signed provided)"
  tls_common_name="$app_host"
  local_cert_path=""
  local_key_path=""

  if [[ "$tls_mode" == "provided" ]]; then
    local_cert_path="$(read_existing_file "Local TLS certificate path" "The provided TLS mode needs a valid local certificate file." "$APP_RUNTIME_PATH")"
    local_key_path="$(read_existing_file "Local TLS private key path" "The provided TLS mode needs a valid local private key file." "$APP_RUNTIME_PATH")"
  fi

  db_name="$(read_required_value "GLPI database name" "MariaDB must create or target the application schema." "$DB_SECRET_PATH")"
  db_user="$(read_required_value "GLPI database username" "The application needs a dedicated database user." "$DB_SECRET_PATH")"
  db_password="$(read_required_value "GLPI database password" "The dedicated database user requires a password." "$DB_SECRET_PATH" true)"
  db_root_password="$(read_required_value "MariaDB root password" "Ansible must secure MariaDB and create the GLPI schema." "$DB_SECRET_PATH" true)"
  exporter_user="$(read_required_value "mysqld_exporter username" "The MariaDB exporter needs a dedicated least-privilege account." "$MONITORING_SECRET_PATH")"
  exporter_password="$(read_required_value "mysqld_exporter password" "The MariaDB exporter account must authenticate locally." "$MONITORING_SECRET_PATH" true)"

  write_runtime_inventory "$INVENTORY_RUNTIME_PATH" "$ENVIRONMENT" "$ssh_user" "$ssh_key" "$app_host" "$db_host"
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

export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
collect_runtime_inputs

if [[ "$MODE" == "check" ]]; then
  write_step "Running pre-flight checks against generated runtime inventory"
  ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
  echo "Pre-flight checks completed successfully."
  exit 0
fi

tags=""
extra_var_files=("$APP_RUNTIME_PATH")

case "$TARGET" in
  base) tags="base" ;;
  app) tags="app" ;;
  db)
    tags="db"
    extra_var_files+=("$DB_SECRET_PATH")
    ;;
  monitoring)
    tags="monitoring"
    extra_var_files+=("$MONITORING_SECRET_PATH" "$DB_SECRET_PATH")
    ;;
  backup) tags="backup" ;;
  all)
    tags="base,app,db,monitoring,backup"
    extra_var_files+=("$DB_SECRET_PATH" "$MONITORING_SECRET_PATH")
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    exit 1
    ;;
esac

case "$MODE" in
  apply)
    write_step "Applying Ansible tags: $tags"
    invoke_ansible "$ENVIRONMENT" "$tags" "${extra_var_files[@]}"
    echo "Apply phase completed."
    ;;
  post-check)
    write_step "Running post-check playbook validation"
    invoke_ansible "$ENVIRONMENT" "app,db" "$APP_RUNTIME_PATH" "$DB_SECRET_PATH"
    echo "Post-check completed."
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac
