#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${GLPI_ENVIRONMENT:-staging}"
export GLPI_ENVIRONMENT="$ENVIRONMENT"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
PROMOTION_DIR="$SCRIPT_ROOT/../.runtime/promotion"
INVENTORY_RUNTIME_PATH="$RUNTIME_DIR/inventory.runtime.yml"
PUBLIC_RUNTIME_PATH="$RUNTIME_DIR/public.runtime.yml"
OVERRIDE_RUNTIME_PATH="$RUNTIME_DIR/overrides.runtime.yml"
SECRET_PATH="$RUNTIME_DIR/secrets.yml"
DB_DEPLOYMENT_MODE="$(resolve_database_deployment_mode_for_environment "$ENVIRONMENT")"
if [[ "$DB_DEPLOYMENT_MODE" == "invalid" ]]; then
  echo "Invalid DATABASE_DEPLOYMENT_MODE in config/$ENVIRONMENT.env (expected self_hosted|managed)." >&2
  exit 1
fi

ensure_runtime_foundation "$ENVIRONMENT"
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" "certify" "run" "all" bash git python3 ansible ansible-playbook ansible-inventory
require_runtime_file "$(config_file_path "$ENVIRONMENT")" "product configuration file"
materialize_runtime_from_config "$ENVIRONMENT"
ensure_secret_keys "$ENVIRONMENT"
ensure_directory_mode "$PROMOTION_DIR" "700"
require_runtime_file "$INVENTORY_RUNTIME_PATH" "runtime inventory"
require_runtime_file "$PUBLIC_RUNTIME_PATH" "public runtime file"
require_runtime_file "$OVERRIDE_RUNTIME_PATH" "runtime override file"
require_runtime_file "$SECRET_PATH" "runtime secret file"
export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"

CERTIFICATION_ID="staging-certification-$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$RUNTIME_DIR/evidence/$CERTIFICATION_ID"
REPORT_PATH="$EVIDENCE_DIR/report.yml"
PROMOTION_GATE_PATH="$PROMOTION_DIR/staging-certified.yml"

ensure_directory_mode "$RUNTIME_DIR/evidence" "700"
ensure_directory_mode "$EVIDENCE_DIR" "700"

run_check() {
  local name="$1"
  local output_file="$2"
  shift 2
  local rc=0
  write_step "Check: $name"
  set +e
  "$@" >"$output_file" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "ok"
  else
    echo "fail"
  fi
  return 0
}

shell_escape_single_quotes() {
  local value="$1"
  value="${value//\'/\'\"\'\"\'}"
  printf "%s" "$value"
}

nginx_check() { ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "nginx -t" -o; }
php_fpm_check() {
  local php_fpm_test_command
  php_fpm_test_command="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_php_fpm_test_command" || true)"
  [[ -z "${php_fpm_test_command// }" ]] && php_fpm_test_command="php-fpm8.3 -t"
  ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "$php_fpm_test_command" -o
}
db_connectivity_check() {
  if [[ "$DB_DEPLOYMENT_MODE" == "managed" ]]; then
    local db_host db_port db_user db_password db_admin_password
    local db_host_escaped db_port_escaped
    local candidate_user candidate_password
    require_runtime_file "$SECRET_PATH" "runtime secret file"
    db_host="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_db_host" || true)"
    db_port="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "mariadb_port" || true)"
    db_user="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_db_user" || true)"
    db_password="$(read_yaml_top_level_value "$SECRET_PATH" "glpi_db_password" || true)"
    db_admin_password="$(read_yaml_top_level_value "$SECRET_PATH" "glpi_db_managed_admin_password" || true)"
    [[ -z "${db_host// }" ]] && { echo "Missing runtime key: glpi_db_host" >&2; return 1; }
    [[ -z "${db_port// }" ]] && db_port="3306"
    [[ -z "${db_user// }" ]] && { echo "Missing runtime key: glpi_db_user" >&2; return 1; }
    [[ -z "${db_password// }" ]] && { echo "Missing runtime secret: glpi_db_password" >&2; return 1; }
    db_host_escaped="$(shell_escape_single_quotes "$db_host")"
    db_port_escaped="$(shell_escape_single_quotes "$db_port")"

    for candidate_user in "$db_user" "root" "admin"; do
      case "$candidate_user" in
        "$db_user") candidate_password="$db_password" ;;
        *)
          if [[ -z "${db_admin_password// }" ]]; then
            echo "Managed DB connectivity: user=${candidate_user} SKIP (DATABASE_MANAGED_ADMIN_PASSWORD not configured)"
            continue
          fi
          candidate_password="$db_admin_password"
          ;;
      esac

      if ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='$(shell_escape_single_quotes "$candidate_password")' mysql --protocol=TCP --host='${db_host_escaped}' --port='${db_port_escaped}' --user='$(shell_escape_single_quotes "$candidate_user")' --execute='SELECT 1;'" -o >/dev/null 2>&1; then
        echo "Managed DB connectivity: user=${candidate_user} PASS"
        return 0
      fi
      echo "Managed DB connectivity: user=${candidate_user} FAIL"
    done
    return 1
  fi
  ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "mysqladmin ping --silent" -o
}

tls_mode="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_mode" || true)"
[[ -z "${tls_mode// }" ]] && tls_mode="$(awk -F'"' '/^glpi_tls_mode:/ {print $2}' "$PUBLIC_RUNTIME_PATH" | head -n1)"
app_domain="$(awk -F'"' '/^glpi_domain:/ {print $2}' "$PUBLIC_RUNTIME_PATH" | head -n1)"
[[ -z "$tls_mode" ]] && tls_mode="none"
smoke_url="http://${app_domain}"
[[ "$tls_mode" != "none" ]] && smoke_url="https://${app_domain}"

smoke_check() {
  if command -v curl >/dev/null 2>&1; then
    curl -k -sS -I --max-time 15 "$smoke_url"
    return 0
  fi
  echo "curl not available on local execution host." >&2
  return 1
}

preflight_status="$(run_check "preflight-summary" "$EVIDENCE_DIR/preflight.log" run_preflight_checks "$ENVIRONMENT" "certify" "run" "all" git ansible ansible-playbook ansible-inventory)"
inventory_status="$(run_check "inventory-parse" "$EVIDENCE_DIR/inventory.log" ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list)"
syntax_status="$(run_check "ansible-syntax" "$EVIDENCE_DIR/ansible-syntax.log" ansible-playbook -i "$INVENTORY_RUNTIME_PATH" "$SCRIPT_ROOT/../ansible/site.yml" --syntax-check --extra-vars "@$PUBLIC_RUNTIME_PATH" --extra-vars "@$OVERRIDE_RUNTIME_PATH" --extra-vars "@$SECRET_PATH")"
nginx_status="$(run_check "nginx-validation" "$EVIDENCE_DIR/nginx.log" nginx_check)"
php_status="$(run_check "php-fpm-validation" "$EVIDENCE_DIR/php-fpm.log" php_fpm_check)"
db_status="$(run_check "db-connectivity" "$EVIDENCE_DIR/db-connectivity.log" db_connectivity_check)"
smoke_status="$(run_check "smoke-test" "$EVIDENCE_DIR/smoke.log" smoke_check)"

overall_status="pass"
for status in "$preflight_status" "$inventory_status" "$syntax_status" "$nginx_status" "$php_status" "$db_status" "$smoke_status"; do
  if [[ "$status" != "ok" ]]; then overall_status="fail"; break; fi
done

cat >"$REPORT_PATH" <<EOF
---
certification_id: '$CERTIFICATION_ID'
environment: '$ENVIRONMENT'
generated_at: '$(date -u +%FT%TZ)'
overall_status: '$overall_status'
checks:
  preflight: '$preflight_status'
  inventory_parse: '$inventory_status'
  ansible_syntax: '$syntax_status'
  nginx_validation: '$nginx_status'
  php_fpm_validation: '$php_status'
  db_connectivity: '$db_status'
  smoke_test: '$smoke_status'
artifacts:
  evidence_dir: '$EVIDENCE_DIR'
  preflight_log: '$EVIDENCE_DIR/preflight.log'
  inventory_log: '$EVIDENCE_DIR/inventory.log'
  ansible_syntax_log: '$EVIDENCE_DIR/ansible-syntax.log'
  nginx_log: '$EVIDENCE_DIR/nginx.log'
  php_fpm_log: '$EVIDENCE_DIR/php-fpm.log'
  db_connectivity_log: '$EVIDENCE_DIR/db-connectivity.log'
  smoke_log: '$EVIDENCE_DIR/smoke.log'
EOF
chmod 600 "$REPORT_PATH"

if [[ "$overall_status" != "pass" ]]; then
  echo "Staging certification failed. Production promotion remains blocked." >&2
  echo "Review report: $REPORT_PATH" >&2
  exit 1
fi

cat >"$PROMOTION_GATE_PATH" <<EOF
---
status: 'approved'
approved_at: '$(date -u +%FT%TZ)'
approved_by: '$(id -un)'
environment_source: 'staging'
certification_id: '$CERTIFICATION_ID'
report_path: '$REPORT_PATH'
evidence_dir: '$EVIDENCE_DIR'
gate_model: 'checklist_and_evidence'
EOF
chmod 600 "$PROMOTION_GATE_PATH"

echo "Staging certification completed successfully."
echo "Promotion gate file: $PROMOTION_GATE_PATH"
