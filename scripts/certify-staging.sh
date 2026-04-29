#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="staging"
RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
PROMOTION_DIR="$SCRIPT_ROOT/../.runtime/promotion"
INVENTORY_RUNTIME_PATH="$RUNTIME_DIR/inventory.runtime.yml"
APP_RUNTIME_PATH="$RUNTIME_DIR/app.runtime.yml"
DB_SECRET_PATH="$RUNTIME_DIR/db.secrets.yml"
MONITORING_SECRET_PATH="$RUNTIME_DIR/monitoring.secrets.yml"

ensure_runtime_foundation "$ENVIRONMENT"
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" git ansible-playbook ansible-inventory
ensure_directory_mode "$PROMOTION_DIR" "700"
require_runtime_file "$INVENTORY_RUNTIME_PATH" "runtime inventory"
require_runtime_file "$APP_RUNTIME_PATH" "application runtime file"
require_runtime_file "$DB_SECRET_PATH" "database secrets file"
require_runtime_file "$MONITORING_SECRET_PATH" "monitoring secrets file"
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

nginx_check() { ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "nginx -t" -o; }
php_fpm_check() { ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "php-fpm8.3 -t" -o; }
db_connectivity_check() { ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "mysqladmin ping --silent" -o; }

tls_mode="$(awk -F'"' '/^glpi_tls_mode:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
app_domain="$(awk -F'"' '/^glpi_domain:/ {print $2}' "$APP_RUNTIME_PATH" | head -n1)"
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

preflight_status="$(run_check "preflight-summary" "$EVIDENCE_DIR/preflight.log" run_preflight_checks "$ENVIRONMENT" git ansible-playbook ansible-inventory)"
inventory_status="$(run_check "inventory-parse" "$EVIDENCE_DIR/inventory.log" ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list)"
syntax_status="$(run_check "ansible-syntax" "$EVIDENCE_DIR/ansible-syntax.log" ansible-playbook -i "$INVENTORY_RUNTIME_PATH" "$SCRIPT_ROOT/../ansible/site.yml" --syntax-check --extra-vars "@$APP_RUNTIME_PATH" --extra-vars "@$DB_SECRET_PATH" --extra-vars "@$MONITORING_SECRET_PATH")"
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
