#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${1:-staging}"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
SECRET_FILE="$RUNTIME_DIR/monitoring.secrets.yml"

ensure_directory "$RUNTIME_DIR"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook
export_runtime_inventory_if_present "$ENVIRONMENT"

exporter_user="$(read_required_value "mysqld_exporter username" "The MariaDB exporter needs a dedicated least-privilege account." "/root/.glpi-secrets/monitoring-runtime.yml")"
exporter_password="$(read_required_value "mysqld_exporter password" "The MariaDB exporter account must authenticate locally." "/root/.glpi-secrets/monitoring-runtime.yml" true)"
db_root_password="$(read_required_value "MariaDB root password" "The exporter user must be created with administrative access." "/root/.glpi-secrets/monitoring-runtime.yml" true)"

save_yaml_map "$SECRET_FILE" \
  mysqld_exporter_user "$exporter_user" \
  mysqld_exporter_password "$exporter_password" \
  glpi_db_root_password "$db_root_password"

write_step "Deploying monitoring role for $ENVIRONMENT"
invoke_ansible "$ENVIRONMENT" "monitoring" "$SECRET_FILE"
