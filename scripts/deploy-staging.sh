#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

MODE="${1:-check}"
TARGET="${2:-all}"
ENVIRONMENT="staging"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"

new_db_secrets() {
  local path="$RUNTIME_DIR/db.secrets.yml"
  local db_name db_user db_password db_root_password
  db_name="$(read_required_value "GLPI database name" "MariaDB must create or target the application schema." "/root/.glpi-secrets/db-runtime.yml")"
  db_user="$(read_required_value "GLPI database username" "The application needs a dedicated database user." "/root/.glpi-secrets/db-runtime.yml")"
  db_password="$(read_required_value "GLPI database password" "The dedicated database user requires a password." "/root/.glpi-secrets/db-runtime.yml" true)"
  db_root_password="$(read_required_value "MariaDB root password" "Ansible must secure MariaDB and create the GLPI schema." "/root/.glpi-secrets/db-runtime.yml" true)"
  save_yaml_map "$path" \
    glpi_db_name "$db_name" \
    glpi_db_user "$db_user" \
    glpi_db_password "$db_password" \
    glpi_db_root_password "$db_root_password"
  printf '%s' "$path"
}

new_monitoring_secrets() {
  local path="$RUNTIME_DIR/monitoring.secrets.yml"
  local exporter_user exporter_password db_root_password
  exporter_user="$(read_required_value "mysqld_exporter username" "The MariaDB exporter needs a dedicated least-privilege account." "/root/.glpi-secrets/monitoring-runtime.yml")"
  exporter_password="$(read_required_value "mysqld_exporter password" "The MariaDB exporter account must authenticate locally." "/root/.glpi-secrets/monitoring-runtime.yml" true)"
  db_root_password="$(read_required_value "MariaDB root password" "The exporter user must be created with administrative access." "/root/.glpi-secrets/monitoring-runtime.yml" true)"
  save_yaml_map "$path" \
    mysqld_exporter_user "$exporter_user" \
    mysqld_exporter_password "$exporter_password" \
    glpi_db_root_password "$db_root_password"
  printf '%s' "$path"
}

ensure_directory "$RUNTIME_DIR"
write_step "Preparing execution for environment '$ENVIRONMENT'"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook ansible-inventory

if [[ "$MODE" == "check" ]]; then
  write_step "Running pre-flight checks"
  ansible-inventory -i "$SCRIPT_ROOT/../ansible/inventories/$ENVIRONMENT/hosts.yml" --list >/dev/null
  echo "Pre-flight checks completed successfully."
  exit 0
fi

tags=""
extra_var_files=()

case "$TARGET" in
  base) tags="base" ;;
  app) tags="app" ;;
  db)
    tags="db"
    extra_var_files+=("$(new_db_secrets)")
    ;;
  monitoring)
    tags="monitoring"
    extra_var_files+=("$(new_monitoring_secrets)")
    ;;
  backup) tags="backup" ;;
  all)
    tags="base,app,db,monitoring,backup"
    extra_var_files+=("$(new_db_secrets)")
    extra_var_files+=("$(new_monitoring_secrets)")
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
    invoke_ansible "$ENVIRONMENT" "app,db" "${extra_var_files[@]}"
    echo "Post-check completed."
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac
