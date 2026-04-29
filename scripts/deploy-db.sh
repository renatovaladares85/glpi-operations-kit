#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${1:-staging}"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
SECRET_FILE="$RUNTIME_DIR/db.secrets.yml"

ensure_directory "$RUNTIME_DIR"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook

db_name="$(read_required_value "GLPI database name" "MariaDB must create or target the application schema." "/root/.glpi-secrets/db-runtime.yml")"
db_user="$(read_required_value "GLPI database username" "The application needs a dedicated database user." "/root/.glpi-secrets/db-runtime.yml")"
db_password="$(read_required_value "GLPI database password" "The dedicated database user requires a password." "/root/.glpi-secrets/db-runtime.yml" true)"
db_root_password="$(read_required_value "MariaDB root password" "Ansible must secure MariaDB and create the GLPI schema." "/root/.glpi-secrets/db-runtime.yml" true)"

save_yaml_map "$SECRET_FILE" \
  glpi_db_name "$db_name" \
  glpi_db_user "$db_user" \
  glpi_db_password "$db_password" \
  glpi_db_root_password "$db_root_password"

write_step "Deploying MariaDB role for $ENVIRONMENT"
invoke_ansible "$ENVIRONMENT" "db" "$SECRET_FILE"
