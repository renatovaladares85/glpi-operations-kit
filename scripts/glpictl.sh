#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
  echo "This CLI is for Linux operational execution only." >&2
  echo "You can edit this repository on Windows, but run deploy/ops commands on Ubuntu hosts." >&2
  exit 1
fi

ENVIRONMENT="${1:-${GLPI_ENVIRONMENT:-}}"
DOMAIN="${2:-}"
ACTION="${3:-}"
TARGET="${4:-all}"
SCOPE="${5:-}"

if [[ -z "$ENVIRONMENT" || -z "$DOMAIN" || -z "$ACTION" ]]; then
  echo "Usage: ./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit|email> <action> [target] [scope]" >&2
  echo "Execution contract: GLPI_ENVIRONMENT, GLPI_EXECUTION_MODE=local|ssh, GLPI_HOST_ROLE=app|db|all, SECURITY_MODE=secure|permissive" >&2
  exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Unsupported environment name: $ENVIRONMENT (allowed: letters, numbers, '.', '-', '_')." >&2
  exit 1
fi

case "$DOMAIN" in
  deploy|certify|promote|tls|ops|audit|email) ;;
  *)
    echo "Unsupported domain: $DOMAIN (expected deploy|certify|promote|tls|ops|audit|email)" >&2
    exit 1
    ;;
esac
export GLPI_ENVIRONMENT="$ENVIRONMENT"

RUNTIME_DIR="$(runtime_env_dir "$ENVIRONMENT")"
INVENTORY_RUNTIME_PATH="$(runtime_inventory_path "$ENVIRONMENT")"
PUBLIC_RUNTIME_PATH="$(runtime_public_path "$ENVIRONMENT")"
OVERRIDE_RUNTIME_PATH="$(runtime_override_path "$ENVIRONMENT")"
SECRET_PATH="$(runtime_secret_path "$ENVIRONMENT")"
CONFIG_PATH="$(config_file_path "$ENVIRONMENT")"
EMAIL_RUNTIME_DIR="$RUNTIME_DIR/email"
EMAIL_AUTH_DIR="$EMAIL_RUNTIME_DIR/auth"
EMAIL_RUNTIME_PATH="$EMAIL_RUNTIME_DIR/mailpit.runtime.yml"
EMAIL_UI_AUTH_FILE="$EMAIL_AUTH_DIR/ui.htpasswd"
EMAIL_SMTP_AUTH_FILE="$EMAIL_AUTH_DIR/smtp.htpasswd"
PROMOTION_GATE_PATH="$SCRIPT_ROOT/../.runtime/promotion/staging-certified.yml"
DEPLOY_SEQUENCE_PATH="$(runtime_state_dir "$ENVIRONMENT")/deploy-sequence.yml"
OPERATION_ID="glpictl-$(date +%Y%m%d-%H%M%S)-${DOMAIN}-${ACTION}-${TARGET}"
OPERATION_STATUS="completed"
OPERATION_LOG_INITIALIZED="false"
FINAL_STATUS_EMITTED="false"
declare -a EXECUTION_WARNINGS=()
EXECUTION_ACCESS_SCHEME="unknown"
EXECUTION_ACCESS_HOST="unknown"
EXECUTION_ACCESS_PORT="0"
EXECUTION_ACCESS_URL="unknown"
EXECUTION_TLS_MODE_EFFECTIVE="unknown"
declare -a EXECUTION_TEST_COMMANDS=()
MANAGED_DB_HOST=""
MANAGED_DB_PORT=""
MANAGED_DB_NAME=""
MANAGED_DB_USER=""
MANAGED_DB_GRANT_HOST=""
MANAGED_DB_PASSWORD=""
MANAGED_DB_ADMIN_PASSWORD=""
MANAGED_DB_TIMEZONE=""
MANAGED_DB_TIMEZONE_SUPPORT_ENABLED="false"
MANAGED_DB_TIMEZONE_MODE="disabled"
MANAGED_DB_TIMEZONE_LEGACY_GRANT="false"

build_execution_test_commands() {
  local web_service php_service
  web_service="$(read_effective_runtime_value "glpi_web_service" "nginx")"
  php_service="$(read_effective_runtime_value "glpi_php_fpm_service" "php8.3-fpm")"
  EXECUTION_TEST_COMMANDS=()
  EXECUTION_TEST_COMMANDS+=("curl -k -I ${EXECUTION_ACCESS_URL}")
  EXECUTION_TEST_COMMANDS+=("sudo nginx -t")
  EXECUTION_TEST_COMMANDS+=("sudo systemctl is-active ${web_service} ${php_service}")
  EXECUTION_TEST_COMMANDS+=("tail -n 50 .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log")
  if [[ "$EXECUTION_ACCESS_SCHEME" == "https" ]]; then
    EXECUTION_TEST_COMMANDS+=("openssl s_client -connect ${EXECUTION_ACCESS_HOST}:${EXECUTION_ACCESS_PORT} -servername ${EXECUTION_ACCESS_HOST} </dev/null 2>/dev/null | openssl x509 -noout -dates")
  fi
}

resolve_execution_access_context() {
  local tls_mode glpi_domain http_port https_port selected_port access_host access_scheme access_url
  tls_mode="$(read_effective_runtime_value "glpi_tls_mode" "")"
  [[ -z "${tls_mode// }" ]] && tls_mode="$(read_product_config_value "$ENVIRONMENT" "tls.mode" || true)"
  [[ -z "${tls_mode// }" ]] && tls_mode="none"

  glpi_domain="$(read_effective_runtime_value "glpi_domain" "")"
  [[ -z "${glpi_domain// }" ]] && glpi_domain="$(read_product_config_value "$ENVIRONMENT" "glpi.domain" || true)"
  [[ -z "${glpi_domain// }" ]] && glpi_domain="unknown-host"

  http_port="$(read_effective_runtime_value "web_http_port" "")"
  [[ -z "${http_port// }" ]] && http_port="$(read_product_config_value "$ENVIRONMENT" "web.http_port" || true)"
  [[ -z "${http_port// }" ]] && http_port="80"

  https_port="$(read_effective_runtime_value "web_https_port" "")"
  [[ -z "${https_port// }" ]] && https_port="$(read_product_config_value "$ENVIRONMENT" "web.https_port" || true)"
  [[ -z "${https_port// }" ]] && https_port="443"

  access_host="$glpi_domain"
  if [[ "$tls_mode" == "none" ]]; then
    access_scheme="http"
    selected_port="$http_port"
  else
    access_scheme="https"
    selected_port="$https_port"
  fi

  access_url="${access_scheme}://${access_host}"
  if [[ "$access_scheme" == "http" && "$selected_port" != "80" ]]; then
    access_url="${access_url}:${selected_port}"
  fi
  if [[ "$access_scheme" == "https" && "$selected_port" != "443" ]]; then
    access_url="${access_url}:${selected_port}"
  fi

  EXECUTION_TLS_MODE_EFFECTIVE="$tls_mode"
  EXECUTION_ACCESS_SCHEME="$access_scheme"
  EXECUTION_ACCESS_HOST="$access_host"
  EXECUTION_ACCESS_PORT="$selected_port"
  EXECUTION_ACCESS_URL="$access_url"
  build_execution_test_commands
}

emit_execution_alert_if_self_signed() {
  if [[ "$EXECUTION_TLS_MODE_EFFECTIVE" == "self_signed" ]]; then
    record_execution_warning "Self-signed TLS certificate in use. Certificate trust warning (certificate not recognized by client trust chain) is expected in staging/lab."
  fi
}

print_execution_final_summary() {
  local status_label="$1"
  local stream="${2:-stdout}"
  local alert_line=""
  local test_cmd=""

  if [[ "$stream" == "stderr" ]]; then
    echo "Execution final summary:" >&2
    echo "  status: ${status_label}" >&2
    echo "  tls_mode: ${EXECUTION_TLS_MODE_EFFECTIVE}" >&2
    echo "  access_url: ${EXECUTION_ACCESS_URL}" >&2
    if [[ ${#EXECUTION_WARNINGS[@]} -eq 0 ]]; then
      echo "  alerts: none" >&2
    else
      echo "  alerts:" >&2
      for alert_line in "${EXECUTION_WARNINGS[@]}"; do
        echo "    - ${alert_line}" >&2
      done
    fi
    echo "  test_commands:" >&2
    for test_cmd in "${EXECUTION_TEST_COMMANDS[@]}"; do
      echo "    - ${test_cmd}" >&2
    done
    return
  fi

  echo "Execution final summary:"
  echo "  status: ${status_label}"
  echo "  tls_mode: ${EXECUTION_TLS_MODE_EFFECTIVE}"
  echo "  access_url: ${EXECUTION_ACCESS_URL}"
  if [[ ${#EXECUTION_WARNINGS[@]} -eq 0 ]]; then
    echo "  alerts: none"
  else
    echo "  alerts:"
    for alert_line in "${EXECUTION_WARNINGS[@]}"; do
      echo "    - ${alert_line}"
    done
  fi
  echo "  test_commands:"
  for test_cmd in "${EXECUTION_TEST_COMMANDS[@]}"; do
    echo "    - ${test_cmd}"
  done
}

summary_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

record_execution_warning() {
  local warning_message="$1"
  EXECUTION_WARNINGS+=("$warning_message")
  echo "WARNING: $warning_message"
}

append_execution_summary_to_file() {
  local summary_path
  local warning_line
  local test_cmd
  summary_path="$(operation_summary_path "$ENVIRONMENT" "$OPERATION_ID")"
  if [[ ! -f "$summary_path" ]]; then
    return 0
  fi
  {
    echo "tls_mode_effective: '$(summary_escape "$EXECUTION_TLS_MODE_EFFECTIVE")'"
    echo "access_scheme: '$(summary_escape "$EXECUTION_ACCESS_SCHEME")'"
    echo "access_host: '$(summary_escape "$EXECUTION_ACCESS_HOST")'"
    echo "access_port: '$(summary_escape "$EXECUTION_ACCESS_PORT")'"
    echo "access_url: '$(summary_escape "$EXECUTION_ACCESS_URL")'"
    echo "alerts_count: ${#EXECUTION_WARNINGS[@]}"
    echo "alerts:"
    if [[ ${#EXECUTION_WARNINGS[@]} -eq 0 ]]; then
      echo "  - 'none'"
    fi
    for warning_line in "${EXECUTION_WARNINGS[@]}"; do
      echo "  - '$(summary_escape "$warning_line")'"
    done
    echo "test_commands:"
    for test_cmd in "${EXECUTION_TEST_COMMANDS[@]}"; do
      echo "  - '$(summary_escape "$test_cmd")'"
    done
  } >>"$summary_path"
}

mask_sensitive_stream() {
  sed -E \
    -e "s/(MYSQL_PWD=)'[^']*'/\1'****'/g" \
    -e "s/(glpi_db_password:[[:space:]]*)'.*'/\1'****'/g" \
    -e "s/(glpi_db_managed_admin_password:[[:space:]]*)'.*'/\1'****'/g" \
    -e "s/(DATABASE_MANAGED_ADMIN_PASSWORD=)[^[:space:]]+/\1****/g" \
    -e "s/(DATABASE_PASSWORD=)[^[:space:]]+/\1****/g"
}

mask_managed_db_secret_values_stream() {
  python3 -c 'import sys
data = sys.stdin.read()
for secret in sys.argv[1:]:
    if secret and secret.strip():
        data = data.replace(secret, "****")
sys.stdout.write(data)
' "$MANAGED_DB_PASSWORD" "$MANAGED_DB_ADMIN_PASSWORD"
}

print_failure_diagnostics() {
  local summary_path log_path
  summary_path="$(operation_summary_path "$ENVIRONMENT" "$OPERATION_ID")"
  log_path="$(operation_log_path "$ENVIRONMENT" "$OPERATION_ID")"

  echo "Failure diagnostics:" >&2
  if [[ -f "$summary_path" ]]; then
    echo "Execution summary content:" >&2
    if [[ -s "$summary_path" ]]; then
      mask_sensitive_stream <"$summary_path" >&2 || true
    else
      echo "Execution summary file exists but is empty." >&2
    fi
  else
    echo "Execution summary file was not created." >&2
  fi

  if [[ -f "$log_path" ]]; then
    echo "Last 80 log lines:" >&2
    tail -n 80 "$log_path" | mask_sensitive_stream >&2 || true
  else
    echo "Execution log file was not created." >&2
  fi
}

finalize_glpictl_operation() {
  local exit_code="${1:-0}"
  if [[ "$FINAL_STATUS_EMITTED" == "true" ]]; then
    return 0
  fi
  FINAL_STATUS_EMITTED="true"

  local remediation_hint="none"
  if [[ "$exit_code" -ne 0 ]]; then
    OPERATION_STATUS="failed"
    remediation_hint="Review console output and .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log"
  fi
  resolve_execution_access_context
  emit_execution_alert_if_self_signed

  if [[ "$OPERATION_LOG_INITIALIZED" == "true" ]]; then
    complete_operation_log "$ENVIRONMENT" "$OPERATION_ID" "$OPERATION_STATUS" "${DOMAIN}/${ACTION}/${TARGET}" "$remediation_hint"
    append_execution_summary_to_file
  fi
  if [[ "$exit_code" -eq 0 ]]; then
    echo "FINAL STATUS: SUCCESS"
    echo "Execution log: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log"
    echo "Execution summary: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.summary.yml"
    if [[ ${#EXECUTION_WARNINGS[@]} -gt 0 ]]; then
      echo "Execution warnings:"
      printf '%s\n' "${EXECUTION_WARNINGS[@]}"
    fi
    print_execution_final_summary "SUCCESS"
    echo "END OF EXECUTION (SUCCESS)"
  else
    echo "FINAL STATUS: FAILED" >&2
    echo "Execution log: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log" >&2
    echo "Execution summary: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.summary.yml" >&2
    print_execution_final_summary "FAILED" "stderr"
    print_failure_diagnostics
    echo "END OF EXECUTION (FAILED)" >&2
  fi
  finish_operation_log_stream
}

handle_signal() {
  local signal_name="$1"
  echo "Execution interrupted by signal: ${signal_name}" >&2
  finalize_glpictl_operation 130
  exit 130
}

print_operation_follow_hints() {
  local log_path summary_path
  log_path="$(operation_log_path "$ENVIRONMENT" "$OPERATION_ID")"
  summary_path="$(operation_summary_path "$ENVIRONMENT" "$OPERATION_ID")"
  echo "Follow this execution live: tail -f $log_path"
  echo "Execution summary file: $summary_path"
}

SECURITY_MODE_EFFECTIVE=""
REQUIRE_TLS="false"
REQUIRE_HTTPS="false"
REQUIRE_PROMOTION_GATE="false"
REQUIRE_ORDERED_EXECUTION="true"
PERMISSIVE_JUSTIFICATION="${SECURITY_JUSTIFICATION:-}"
PERMISSIVE_EVIDENCE_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PERMISSIVE_EVIDENCE_STATE_PATH="$(runtime_state_dir "$ENVIRONMENT")/security-mode-last.yml"
PERMISSIVE_EVIDENCE_REPORT_PATH="$(runtime_evidence_dir "$ENVIRONMENT")/security-mode-${PERMISSIVE_EVIDENCE_TIMESTAMP}-${DOMAIN}-${ACTION}.yml"
declare -a POLICY_VIOLATIONS=()
EXECUTION_MODE_EFFECTIVE=""
HOST_ROLE_EFFECTIVE=""
TOPOLOGY_MODE_EFFECTIVE="dual-server"
ASSUME_DB_APPLIED="false"
DB_DEPLOYMENT_MODE_EFFECTIVE="self_hosted"
normalize_bool() {
  local value="$1"
  local default_value="${2:-false}"
  case "$value" in
    true|false) echo "$value" ;;
    *) echo "$default_value" ;;
  esac
}

is_managed_database_mode() {
  [[ "$DB_DEPLOYMENT_MODE_EFFECTIVE" == "managed" ]]
}

yaml_escape() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
}

shell_escape_single_quotes() {
  local value="$1"
  value="${value//\'/\'\"\'\"\'}"
  printf "%s" "$value"
}

read_effective_runtime_value() {
  local key="$1"
  local default_value="${2:-}"
  local value
  value="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "$key" || true)"
  [[ -z "${value// }" ]] && value="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "$key" || true)"
  [[ -z "${value// }" ]] && value="$default_value"
  echo "$value"
}

version_gte() {
  local current="$1"
  local minimum="$2"
  [[ "$(printf '%s\n%s\n' "$minimum" "$current" | sort -V | head -n1)" == "$minimum" ]]
}

domain_evidence_dir_path() {
  local domain_name="$1"
  echo "$(runtime_evidence_dir "$ENVIRONMENT")/${domain_name}"
}

domain_state_path() {
  local domain_name="$1"
  echo "$(runtime_state_dir "$ENVIRONMENT")/${domain_name}-state.yml"
}

domain_backup_state_path() {
  local domain_name="$1"
  echo "$(runtime_state_dir "$ENVIRONMENT")/${domain_name}-backup-latest.yml"
}

domain_backup_root_dir() {
  local domain_name="$1"
  echo "$(runtime_env_dir "$ENVIRONMENT")/backups/${domain_name}"
}

ensure_domain_evidence_dir() {
  local domain_name="$1"
  local evidence_dir
  evidence_dir="$(domain_evidence_dir_path "$domain_name")"
  ensure_directory "$evidence_dir"
  chmod 700 "$evidence_dir" >/dev/null 2>&1 || true
}

write_domain_state() {
  local domain_name="$1"
  local action_name="$2"
  local status="$3"
  local details="$4"
  local state_path
  state_path="$(domain_state_path "$domain_name")"
  save_yaml_map "$state_path" \
    domain "$domain_name" \
    environment "$ENVIRONMENT" \
    action "$action_name" \
    status "$status" \
    details "$details" \
    updated_at_utc "$(date -u +%FT%TZ)"
}

capture_mode_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    stat -c '%a' "$path" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

backup_copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    ensure_directory "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

latest_domain_backup_dir() {
  local domain_name="$1"
  read_yaml_top_level_value "$(domain_backup_state_path "$domain_name")" "backup_dir" || true
}

inventory_group_has_hosts() {
  local group_name="$1"
  python3 - "$INVENTORY_RUNTIME_PATH" "$group_name" <<'PY'
import sys
from pathlib import Path
import yaml

inventory_path = Path(sys.argv[1])
group_name = sys.argv[2]
if not inventory_path.exists():
    print("false")
    sys.exit(0)
data = yaml.safe_load(inventory_path.read_text(encoding="utf-8")) or {}
hosts = (
    (data.get("all") or {})
    .get("children", {})
    .get(group_name, {})
    .get("hosts", {})
)
print("true" if isinstance(hosts, dict) and len(hosts) > 0 else "false")
PY
}

domain_action_requires_remote_app_snapshot() {
  local domain_name="$1"
  local action_name="$2"
  local target_name="$3"
  local scope_name="${4:-}"
  case "$domain_name/$action_name" in
    deploy/apply)
      case "$target_name" in
        app|monitoring|backup|all) return 0 ;;
      esac
      ;;
    promote/apply)
      case "$target_name" in
        app|monitoring|backup|all) return 0 ;;
      esac
      ;;
    tls/apply|tls/disable|tls/self-signed|tls/install-provided|tls/reload) return 0 ;;
    ops/users)
      case "$scope_name" in
        os|glpi|"") return 0 ;;
      esac
      ;;
    ops/cert|ops/resume) return 0 ;;
    ops/timezone)
      if [[ "$target_name" == "apply" ]]; then
        return 0
      fi
      ;;
    email/install|email/rollback) return 0 ;;
  esac
  return 1
}

domain_action_requires_remote_db_snapshot() {
  local domain_name="$1"
  local action_name="$2"
  local target_name="$3"
  local scope_name="$4"
  case "$domain_name/$action_name" in
    deploy/apply)
      case "$target_name" in
        db|all) return 0 ;;
      esac
      ;;
    promote/apply)
      case "$target_name" in
        db|all) return 0 ;;
      esac
      ;;
    ops/users)
      if [[ "$scope_name" == "db" ]]; then
        return 0
      fi
      ;;
    ops/timezone)
      if [[ "$target_name" == "apply" ]] && ! is_managed_database_mode; then
        return 0
      fi
      ;;
  esac
  return 1
}

domain_action_requires_remote_snapshot() {
  local domain_name="$1"
  local action_name="$2"
  local target_name="$3"
  local scope_name="$4"
  if domain_action_requires_remote_app_snapshot "$domain_name" "$action_name" "$target_name" "$scope_name"; then
    return 0
  fi
  if domain_action_requires_remote_db_snapshot "$domain_name" "$action_name" "$target_name" "$scope_name"; then
    return 0
  fi
  return 1
}

remote_snapshot_root_for_backup() {
  local domain_name="$1"
  local backup_dir="$2"
  local remote_base timestamp
  remote_base="$(read_effective_runtime_value "glpi_backup_base_dir" "/var/backups/glpi")"
  timestamp="$(basename "$backup_dir")"
  echo "${remote_base%/}/opskit/${ENVIRONMENT}/${domain_name}/${timestamp}"
}

create_remote_domain_backup_snapshot() {
  local domain_name="$1"
  local action_name="$2"
  local target_name="$3"
  local scope_name="$4"
  local backup_dir remote_root remote_backup_file manifest_path
  local app_required db_required app_has_hosts db_has_hosts
  local glpi_install_dir glpi_config_dir glpi_var_dir glpi_plugin_dir glpi_log_dir glpi_db_name
  local db_root_password db_root_password_escaped remote_root_escaped
  local app_cmd db_cmd

  if ! domain_action_requires_remote_snapshot "$domain_name" "$action_name" "$target_name" "$scope_name"; then
    return 0
  fi

  backup_dir="$(latest_domain_backup_dir "$domain_name")"
  if [[ -z "${backup_dir// }" || ! -d "$backup_dir" ]]; then
    echo "Unable to resolve backup directory for remote snapshot (${domain_name}/${action_name})." >&2
    exit 1
  fi

  app_required="false"
  db_required="false"
  domain_action_requires_remote_app_snapshot "$domain_name" "$action_name" "$target_name" "$scope_name" && app_required="true"
  domain_action_requires_remote_db_snapshot "$domain_name" "$action_name" "$target_name" "$scope_name" && db_required="true"

  app_has_hosts="false"
  db_has_hosts="false"
  [[ "$(inventory_group_has_hosts "glpi_app")" == "true" ]] && app_has_hosts="true"
  [[ "$(inventory_group_has_hosts "glpi_db")" == "true" ]] && db_has_hosts="true"

  remote_root="$(remote_snapshot_root_for_backup "$domain_name" "$backup_dir")"
  remote_backup_file="${backup_dir}/REMOTE_BACKUP.yml"
  manifest_path="${backup_dir}/MANIFEST.md"
  remote_root_escaped="$(shell_escape_single_quotes "$remote_root")"

  if [[ "$app_required" == "true" && "$app_has_hosts" == "true" ]]; then
    glpi_install_dir="$(read_effective_runtime_value "glpi_install_dir" "/usr/share/glpi")"
    glpi_config_dir="$(read_effective_runtime_value "glpi_config_dir" "/etc/glpi")"
    glpi_var_dir="$(read_effective_runtime_value "glpi_var_dir" "/var/lib/glpi/files")"
    glpi_plugin_dir="$(read_effective_runtime_value "glpi_plugin_dir" "/var/lib/glpi/plugins")"
    glpi_log_dir="$(read_effective_runtime_value "glpi_log_dir" "/var/log/glpi")"

    app_cmd="set -eu; ROOT='${remote_root_escaped}/{{ inventory_hostname }}/app'; mkdir -p \"\$ROOT\"; chmod 700 \"\$ROOT\"; MANIFEST=\"\$ROOT/MANIFEST.paths\"; : > \"\$MANIFEST\"; for p in '$(shell_escape_single_quotes "$glpi_install_dir")' '$(shell_escape_single_quotes "$glpi_config_dir")' '$(shell_escape_single_quotes "$glpi_var_dir")' '$(shell_escape_single_quotes "$glpi_plugin_dir")' '$(shell_escape_single_quotes "$glpi_log_dir")' '/etc/nginx' '/etc/apache2' '/etc/httpd' '/etc/lighttpd' '/etc/php' '/etc/passwd' '/etc/group' '/etc/shadow'; do if [ -e \"\$p\" ]; then printf '%s\n' \"\$p\" >> \"\$MANIFEST\"; fi; done; if [ -s \"\$MANIFEST\" ]; then tar --absolute-names -czf \"\$ROOT/files.tar.gz\" --files-from \"\$MANIFEST\"; else touch \"\$ROOT/EMPTY\"; tar -czf \"\$ROOT/files.tar.gz\" -C \"\$ROOT\" EMPTY; fi; while IFS= read -r path; do [ -e \"\$path\" ] && stat -c '%a %n' \"\$path\" || true; done < \"\$MANIFEST\" > \"\$ROOT/PERMISSIONS.txt\""
    if ! ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "$app_cmd" -o; then
      echo "Remote snapshot failed on APP hosts before '${domain_name}/${action_name}/${target_name}'." >&2
      echo "Cannot continue safely without a valid APP pre-change snapshot." >&2
      exit 1
    fi
  fi

  if [[ "$db_required" == "true" && "$db_has_hosts" == "true" ]]; then
    require_runtime_file "$SECRET_PATH" "runtime secret file"
    db_root_password="$(read_yaml_top_level_value "$SECRET_PATH" "glpi_db_root_password" || true)"
    if [[ -z "${db_root_password// }" ]]; then
      echo "Missing runtime secret: glpi_db_root_password (required for DB snapshot)." >&2
      exit 1
    fi
    db_root_password_escaped="$(shell_escape_single_quotes "$db_root_password")"
    glpi_db_name="$(read_effective_runtime_value "glpi_db_name" "")"
    if [[ -z "${glpi_db_name// }" ]]; then
      echo "Missing runtime key: glpi_db_name (required for DB snapshot)." >&2
      exit 1
    fi
    db_cmd="set -eu; ROOT='${remote_root_escaped}/{{ inventory_hostname }}/db'; mkdir -p \"\$ROOT\"; chmod 700 \"\$ROOT\"; MANIFEST=\"\$ROOT/MANIFEST.paths\"; : > \"\$MANIFEST\"; for p in '/etc/mysql' '/var/lib/mysql' '/etc/my.cnf' '/etc/my.cnf.d'; do if [ -e \"\$p\" ]; then printf '%s\n' \"\$p\" >> \"\$MANIFEST\"; fi; done; if [ -s \"\$MANIFEST\" ]; then tar --absolute-names -czf \"\$ROOT/files.tar.gz\" --files-from \"\$MANIFEST\"; else touch \"\$ROOT/EMPTY\"; tar -czf \"\$ROOT/files.tar.gz\" -C \"\$ROOT\" EMPTY; fi; while IFS= read -r path; do [ -e \"\$path\" ] && stat -c '%a %n' \"\$path\" || true; done < \"\$MANIFEST\" > \"\$ROOT/PERMISSIONS.txt\"; mysqldump --single-transaction --routines --events --triggers --databases '$(shell_escape_single_quotes "$glpi_db_name")' -u root -p'${db_root_password_escaped}' > \"\$ROOT/glpi-db.sql\""
    if ! ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "$db_cmd" -o; then
      echo "Remote snapshot failed on DB hosts before '${domain_name}/${action_name}/${target_name}'." >&2
      echo "Cannot continue safely without a valid DB pre-change snapshot." >&2
      exit 1
    fi
  fi

  cat >"$remote_backup_file" <<EOF
---
domain: '$(yaml_escape "$domain_name")'
action: '$(yaml_escape "$action_name")'
target: '$(yaml_escape "$target_name")'
scope: '$(yaml_escape "$scope_name")'
environment: '$(yaml_escape "$ENVIRONMENT")'
created_at_utc: '$(date -u +%FT%TZ)'
remote_root: '$(yaml_escape "$remote_root")'
app_snapshot_required: $(yaml_escape "$app_required")
db_snapshot_required: $(yaml_escape "$db_required")
app_hosts_detected: $(yaml_escape "$app_has_hosts")
db_hosts_detected: $(yaml_escape "$db_has_hosts")
EOF
  chmod 600 "$remote_backup_file"

  {
    echo ""
    echo "## Remote Snapshot"
    echo ""
    echo "- REMOTE_BACKUP.yml"
    echo "- remote_root: \`$remote_root\`"
    echo "- app_snapshot_required: \`$app_required\` (hosts_detected=\`$app_has_hosts\`)"
    echo "- db_snapshot_required: \`$db_required\` (hosts_detected=\`$db_has_hosts\`)"
  } >>"$manifest_path"
}

restore_remote_domain_backup_snapshot() {
  local domain_name="$1"
  local backup_dir="$2"
  local remote_backup_file remote_root app_required db_required app_has_hosts db_has_hosts
  local db_root_password db_root_password_escaped
  local app_restore_cmd db_restore_cmd

  remote_backup_file="${backup_dir}/REMOTE_BACKUP.yml"
  if [[ ! -f "$remote_backup_file" ]]; then
    return 0
  fi

  remote_root="$(read_yaml_top_level_value "$remote_backup_file" "remote_root" || true)"
  app_required="$(normalize_bool "$(read_yaml_top_level_value "$remote_backup_file" "app_snapshot_required" || true)" "false")"
  db_required="$(normalize_bool "$(read_yaml_top_level_value "$remote_backup_file" "db_snapshot_required" || true)" "false")"
  app_has_hosts="$(normalize_bool "$(read_yaml_top_level_value "$remote_backup_file" "app_hosts_detected" || true)" "false")"
  db_has_hosts="$(normalize_bool "$(read_yaml_top_level_value "$remote_backup_file" "db_hosts_detected" || true)" "false")"
  if [[ -z "${remote_root// }" ]]; then
    return 0
  fi

  if [[ "$app_required" == "true" && "$app_has_hosts" == "true" ]]; then
    app_restore_cmd="set -eu; ROOT='$(shell_escape_single_quotes "$remote_root")/{{ inventory_hostname }}/app'; if [ -f \"\$ROOT/files.tar.gz\" ]; then tar -xzf \"\$ROOT/files.tar.gz\" -C /; fi; if [ -f \"\$ROOT/PERMISSIONS.txt\" ]; then while IFS= read -r line; do mode=\"\${line%% *}\"; path=\"\${line#* }\"; if [ -n \"\${mode// }\" ] && [ -e \"\$path\" ]; then chmod \"\$mode\" \"\$path\" || true; fi; done < \"\$ROOT/PERMISSIONS.txt\"; fi"
    ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "$app_restore_cmd" -o >/dev/null
  fi

  if [[ "$db_required" == "true" && "$db_has_hosts" == "true" ]]; then
    require_runtime_file "$SECRET_PATH" "runtime secret file"
    db_root_password="$(read_yaml_top_level_value "$SECRET_PATH" "glpi_db_root_password" || true)"
    if [[ -z "${db_root_password// }" ]]; then
      echo "Missing runtime secret: glpi_db_root_password (required for DB restore)." >&2
      exit 1
    fi
    db_root_password_escaped="$(shell_escape_single_quotes "$db_root_password")"
    db_restore_cmd="set -eu; ROOT='$(shell_escape_single_quotes "$remote_root")/{{ inventory_hostname }}/db'; if [ -f \"\$ROOT/files.tar.gz\" ]; then tar -xzf \"\$ROOT/files.tar.gz\" -C /; fi; if [ -f \"\$ROOT/PERMISSIONS.txt\" ]; then while IFS= read -r line; do mode=\"\${line%% *}\"; path=\"\${line#* }\"; if [ -n \"\${mode// }\" ] && [ -e \"\$path\" ]; then chmod \"\$mode\" \"\$path\" || true; fi; done < \"\$ROOT/PERMISSIONS.txt\"; fi; if [ -f \"\$ROOT/glpi-db.sql\" ]; then mysql -u root -p'${db_root_password_escaped}' < \"\$ROOT/glpi-db.sql\"; fi"
    ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "$db_restore_cmd" -o >/dev/null
  fi
}

create_domain_backup_snapshot() {
  local domain_name="$1"
  local action_name="$2"
  local timestamp backup_root backup_dir backup_files_dir backup_state_path
  local evidence_dir domain_state_file state_before_path manifest_path rollback_path
  local deploy_sequence_file deploy_sequence_exists deploy_sequence_mode
  local config_exists public_exists evidence_exists state_exists override_exists promotion_gate_exists
  local config_mode public_mode evidence_mode state_mode override_mode promotion_gate_mode

  timestamp="$(date -u +%Y%m%dT%H%M%S%NZ)"
  backup_root="$(domain_backup_root_dir "$domain_name")"
  backup_dir="${backup_root}/${timestamp}"
  backup_files_dir="${backup_dir}/files"
  backup_state_path="$(domain_backup_state_path "$domain_name")"
  evidence_dir="$(domain_evidence_dir_path "$domain_name")"
  domain_state_file="$(domain_state_path "$domain_name")"
  deploy_sequence_file="${DEPLOY_SEQUENCE_PATH}"
  config_exists="false"
  public_exists="false"
  state_before_path="${backup_dir}/STATE_BEFORE.yml"
  manifest_path="${backup_dir}/MANIFEST.md"
  rollback_path="${backup_dir}/ROLLBACK.md"

  ensure_directory "$backup_root"
  chmod 700 "$backup_root" >/dev/null 2>&1 || true
  ensure_directory "$backup_files_dir"
  chmod 700 "$backup_dir" "$backup_files_dir" >/dev/null 2>&1 || true

  override_exists="false"
  evidence_exists="false"
  state_exists="false"
  deploy_sequence_exists="false"
  promotion_gate_exists="false"
  [[ -e "$OVERRIDE_RUNTIME_PATH" ]] && override_exists="true"
  [[ -e "$CONFIG_PATH" ]] && config_exists="true"
  [[ -e "$PUBLIC_RUNTIME_PATH" ]] && public_exists="true"
  [[ -e "$evidence_dir" ]] && evidence_exists="true"
  [[ -e "$domain_state_file" ]] && state_exists="true"
  if [[ "$domain_name" == "deploy" && -e "$deploy_sequence_file" ]]; then
    deploy_sequence_exists="true"
  fi
  if [[ "$domain_name" == "certify" && -e "$PROMOTION_GATE_PATH" ]]; then
    promotion_gate_exists="true"
  fi

  config_mode="$(capture_mode_if_exists "$CONFIG_PATH")"
  public_mode="$(capture_mode_if_exists "$PUBLIC_RUNTIME_PATH")"
  override_mode="$(capture_mode_if_exists "$OVERRIDE_RUNTIME_PATH")"
  evidence_mode="$(capture_mode_if_exists "$evidence_dir")"
  state_mode="$(capture_mode_if_exists "$domain_state_file")"
  deploy_sequence_mode="$(capture_mode_if_exists "$deploy_sequence_file")"
  promotion_gate_mode="$(capture_mode_if_exists "$PROMOTION_GATE_PATH")"

  backup_copy_if_exists "$OVERRIDE_RUNTIME_PATH" "${backup_files_dir}/overrides.runtime.yml"
  backup_copy_if_exists "$PUBLIC_RUNTIME_PATH" "${backup_files_dir}/public.runtime.yml"
  backup_copy_if_exists "$CONFIG_PATH" "${backup_files_dir}/environment.config.env"
  backup_copy_if_exists "$evidence_dir" "${backup_files_dir}/${domain_name}-evidence"
  backup_copy_if_exists "$domain_state_file" "${backup_files_dir}/${domain_name}-state.yml"
  if [[ "$domain_name" == "deploy" ]]; then
    backup_copy_if_exists "$deploy_sequence_file" "${backup_files_dir}/deploy-sequence.yml"
  fi
  if [[ "$domain_name" == "certify" ]]; then
    backup_copy_if_exists "$PROMOTION_GATE_PATH" "${backup_files_dir}/promotion-gate.yml"
  fi

  cat >"$state_before_path" <<EOF
---
domain: '$(yaml_escape "$domain_name")'
environment: '$(yaml_escape "$ENVIRONMENT")'
action: '$(yaml_escape "$action_name")'
created_at_utc: '$(date -u +%FT%TZ)'
environment_config_path: '$(yaml_escape "$CONFIG_PATH")'
environment_config_exists_before: $(yaml_escape "$config_exists")
environment_config_mode_before: '$(yaml_escape "$config_mode")'
public_runtime_path: '$(yaml_escape "$PUBLIC_RUNTIME_PATH")'
public_runtime_exists_before: $(yaml_escape "$public_exists")
public_runtime_mode_before: '$(yaml_escape "$public_mode")'
override_runtime_path: '$(yaml_escape "$OVERRIDE_RUNTIME_PATH")'
override_exists_before: $(yaml_escape "$override_exists")
override_mode_before: '$(yaml_escape "$override_mode")'
domain_evidence_dir: '$(yaml_escape "$evidence_dir")'
domain_evidence_exists_before: $(yaml_escape "$evidence_exists")
domain_evidence_mode_before: '$(yaml_escape "$evidence_mode")'
domain_state_path: '$(yaml_escape "$domain_state_file")'
domain_state_exists_before: $(yaml_escape "$state_exists")
domain_state_mode_before: '$(yaml_escape "$state_mode")'
deploy_sequence_path: '$(yaml_escape "$deploy_sequence_file")'
deploy_sequence_exists_before: $(yaml_escape "$deploy_sequence_exists")
deploy_sequence_mode_before: '$(yaml_escape "$deploy_sequence_mode")'
promotion_gate_path: '$(yaml_escape "$PROMOTION_GATE_PATH")'
promotion_gate_exists_before: $(yaml_escape "$promotion_gate_exists")
promotion_gate_mode_before: '$(yaml_escape "$promotion_gate_mode")'
EOF

  cat >"$manifest_path" <<EOF
# ${domain_name} Backup Manifest

- environment: \`$ENVIRONMENT\`
- domain: \`$domain_name\`
- action: \`$action_name\`
- backup_dir: \`$backup_dir\`
- created_at_utc: \`$(date -u +%FT%TZ)\`

## Snapshot Contents

- files/overrides.runtime.yml
- files/public.runtime.yml
- files/environment.config.env
- files/${domain_name}-evidence/
- files/${domain_name}-state.yml
- files/deploy-sequence.yml (deploy domain only)
- files/promotion-gate.yml (certify domain only)
- STATE_BEFORE.yml
- ROLLBACK.md
EOF

  cat >"$rollback_path" <<EOF
# ${domain_name} Rollback Instructions

This backup can be restored using:

\`\`\`bash
./scripts/glpictl.sh $ENVIRONMENT ${domain_name} rollback
\`\`\`

Rollback source directory:

\`$backup_dir\`
EOF

  chmod 600 "$state_before_path" "$manifest_path" "$rollback_path"
  save_yaml_map "$backup_state_path" \
    domain "$domain_name" \
    environment "$ENVIRONMENT" \
    action "$action_name" \
    backup_dir "$backup_dir" \
    created_at_utc "$(date -u +%FT%TZ)"
}

find_domain_backup_for_restore() {
  local domain_name="$1"
  local prefer_previous="${2:-false}"
  local backup_root
  backup_root="$(domain_backup_root_dir "$domain_name")"
  if [[ ! -d "$backup_root" ]]; then
    echo ""
    return 0
  fi

  mapfile -t backups < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | sort)
  if ((${#backups[@]} == 0)); then
    echo ""
    return 0
  fi
  if [[ "$prefer_previous" == "true" ]]; then
    if ((${#backups[@]} < 2)); then
      echo ""
      return 0
    fi
    echo "${backups[$((${#backups[@]} - 2))]}"
    return 0
  fi
  echo "${backups[$((${#backups[@]} - 1))]}"
}

restore_domain_permissions_from_state() {
  local domain_name="$1"
  local state_file="$2"
  local evidence_dir domain_state_file deploy_sequence_file
  local config_mode public_mode override_mode evidence_mode state_mode deploy_sequence_mode promotion_gate_mode

  evidence_dir="$(domain_evidence_dir_path "$domain_name")"
  domain_state_file="$(domain_state_path "$domain_name")"
  deploy_sequence_file="${DEPLOY_SEQUENCE_PATH}"
  config_mode="$(read_yaml_top_level_value "$state_file" "environment_config_mode_before" || true)"
  public_mode="$(read_yaml_top_level_value "$state_file" "public_runtime_mode_before" || true)"
  override_mode="$(read_yaml_top_level_value "$state_file" "override_mode_before" || true)"
  evidence_mode="$(read_yaml_top_level_value "$state_file" "domain_evidence_mode_before" || true)"
  state_mode="$(read_yaml_top_level_value "$state_file" "domain_state_mode_before" || true)"
  deploy_sequence_mode="$(read_yaml_top_level_value "$state_file" "deploy_sequence_mode_before" || true)"
  promotion_gate_mode="$(read_yaml_top_level_value "$state_file" "promotion_gate_mode_before" || true)"

  if [[ -n "${config_mode// }" && -e "$CONFIG_PATH" ]]; then
    chmod "$config_mode" "$CONFIG_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "${public_mode// }" && -e "$PUBLIC_RUNTIME_PATH" ]]; then
    chmod "$public_mode" "$PUBLIC_RUNTIME_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "${override_mode// }" && -e "$OVERRIDE_RUNTIME_PATH" ]]; then
    chmod "$override_mode" "$OVERRIDE_RUNTIME_PATH" >/dev/null 2>&1 || true
  fi
  if [[ -n "${evidence_mode// }" && -e "$evidence_dir" ]]; then
    chmod "$evidence_mode" "$evidence_dir" >/dev/null 2>&1 || true
  fi
  if [[ -n "${state_mode// }" && -e "$domain_state_file" ]]; then
    chmod "$state_mode" "$domain_state_file" >/dev/null 2>&1 || true
  fi
  if [[ "$domain_name" == "deploy" ]] && [[ -n "${deploy_sequence_mode// }" && -e "$deploy_sequence_file" ]]; then
    chmod "$deploy_sequence_mode" "$deploy_sequence_file" >/dev/null 2>&1 || true
  fi
  if [[ "$domain_name" == "certify" ]] && [[ -n "${promotion_gate_mode// }" && -e "$PROMOTION_GATE_PATH" ]]; then
    chmod "$promotion_gate_mode" "$PROMOTION_GATE_PATH" >/dev/null 2>&1 || true
  fi
}

run_domain_metadata_restore_from_backup() {
  local domain_name="$1"
  local backup_dir="$2"
  local backup_files_dir state_before_file config_exists_before public_exists_before evidence_exists_before state_exists_before
  local deploy_sequence_exists_before promotion_gate_exists_before deploy_sequence_file
  local evidence_dir domain_state_file

  evidence_dir="$(domain_evidence_dir_path "$domain_name")"
  domain_state_file="$(domain_state_path "$domain_name")"
  deploy_sequence_file="${DEPLOY_SEQUENCE_PATH}"
  if [[ -z "${backup_dir// }" || ! -d "$backup_dir" ]]; then
    echo "No ${domain_name} backup found to restore under $(domain_backup_root_dir "$domain_name")." >&2
    exit 1
  fi

  backup_files_dir="${backup_dir}/files"
  state_before_file="${backup_dir}/STATE_BEFORE.yml"
  if [[ ! -f "$state_before_file" ]]; then
    echo "Invalid ${domain_name} backup: missing STATE_BEFORE.yml in $backup_dir." >&2
    exit 1
  fi

  if [[ -f "${backup_files_dir}/overrides.runtime.yml" ]]; then
    cp -a "${backup_files_dir}/overrides.runtime.yml" "$OVERRIDE_RUNTIME_PATH"
  fi

  config_exists_before="$(read_yaml_top_level_value "$state_before_file" "environment_config_exists_before" || true)"
  if [[ -f "${backup_files_dir}/environment.config.env" ]]; then
    cp -a "${backup_files_dir}/environment.config.env" "$CONFIG_PATH"
  elif [[ "$config_exists_before" != "true" && -f "$CONFIG_PATH" ]]; then
    rm -f "$CONFIG_PATH"
  fi

  public_exists_before="$(read_yaml_top_level_value "$state_before_file" "public_runtime_exists_before" || true)"
  if [[ -f "${backup_files_dir}/public.runtime.yml" ]]; then
    cp -a "${backup_files_dir}/public.runtime.yml" "$PUBLIC_RUNTIME_PATH"
  elif [[ "$public_exists_before" != "true" && -f "$PUBLIC_RUNTIME_PATH" ]]; then
    rm -f "$PUBLIC_RUNTIME_PATH"
  fi

  evidence_exists_before="$(read_yaml_top_level_value "$state_before_file" "domain_evidence_exists_before" || true)"
  if [[ -d "$evidence_dir" ]]; then
    rm -rf "$evidence_dir"
  fi
  if [[ -d "${backup_files_dir}/${domain_name}-evidence" ]]; then
    cp -a "${backup_files_dir}/${domain_name}-evidence" "$evidence_dir"
  elif [[ "$evidence_exists_before" == "true" ]]; then
    ensure_directory "$evidence_dir"
  fi

  state_exists_before="$(read_yaml_top_level_value "$state_before_file" "domain_state_exists_before" || true)"
  if [[ -f "${backup_files_dir}/${domain_name}-state.yml" ]]; then
    cp -a "${backup_files_dir}/${domain_name}-state.yml" "$domain_state_file"
  elif [[ "$state_exists_before" != "true" && -f "$domain_state_file" ]]; then
    rm -f "$domain_state_file"
  fi

  if [[ "$domain_name" == "deploy" ]]; then
    deploy_sequence_exists_before="$(read_yaml_top_level_value "$state_before_file" "deploy_sequence_exists_before" || true)"
    if [[ -f "${backup_files_dir}/deploy-sequence.yml" ]]; then
      cp -a "${backup_files_dir}/deploy-sequence.yml" "$deploy_sequence_file"
    elif [[ "$deploy_sequence_exists_before" != "true" && -f "$deploy_sequence_file" ]]; then
      rm -f "$deploy_sequence_file"
    fi
  fi

  if [[ "$domain_name" == "certify" ]]; then
    promotion_gate_exists_before="$(read_yaml_top_level_value "$state_before_file" "promotion_gate_exists_before" || true)"
    if [[ -f "${backup_files_dir}/promotion-gate.yml" ]]; then
      cp -a "${backup_files_dir}/promotion-gate.yml" "$PROMOTION_GATE_PATH"
    elif [[ "$promotion_gate_exists_before" != "true" && -f "$PROMOTION_GATE_PATH" ]]; then
      rm -f "$PROMOTION_GATE_PATH"
    fi
  fi

  restore_domain_permissions_from_state "$domain_name" "$state_before_file"
}

run_domain_metadata_rollback() {
  local domain_name="$1"
  local prefer_previous="${2:-false}"
  local backup_dir
  backup_dir="$(find_domain_backup_for_restore "$domain_name" "$prefer_previous")"
  run_domain_metadata_restore_from_backup "$domain_name" "$backup_dir"
}

write_domain_evidence_simple() {
  local domain_name="$1"
  local action_name="$2"
  local status="$3"
  local notes="$4"
  local timestamp evidence_dir report_md report_yml latest_md latest_yml

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  ensure_domain_evidence_dir "$domain_name"
  evidence_dir="$(domain_evidence_dir_path "$domain_name")"
  report_md="$evidence_dir/${action_name}-${timestamp}.md"
  report_yml="$evidence_dir/${action_name}-${timestamp}.yml"
  latest_md="$evidence_dir/${action_name}-latest.md"
  latest_yml="$evidence_dir/${action_name}-latest.yml"

  cat >"$report_md" <<EOF
# ${domain_name} ${action_name} Evidence

- environment: \`$ENVIRONMENT\`
- domain: \`$domain_name\`
- status: \`$status\`
- generated_at_utc: \`$(date -u +%FT%TZ)\`

## Notes

$notes
EOF

  cat >"$report_yml" <<EOF
---
environment: '$(yaml_escape "$ENVIRONMENT")'
domain: '$(yaml_escape "$domain_name")'
action: '$(yaml_escape "$action_name")'
status: '$(yaml_escape "$status")'
generated_at_utc: '$(date -u +%FT%TZ)'
notes: '$(yaml_escape "$notes")'
EOF

  chmod 600 "$report_md" "$report_yml"
  cp "$report_md" "$latest_md"
  cp "$report_yml" "$latest_yml"
  chmod 600 "$latest_md" "$latest_yml"
}

read_policy_flag() {
  local key="$1"
  local legacy_key="$2"
  local default_value="$3"
  local value
  value="$(read_product_config_value "$ENVIRONMENT" "$key" || true)"
  if [[ -z "${value// }" && -n "${legacy_key// }" ]]; then
    value="$(read_product_config_value "$ENVIRONMENT" "$legacy_key" || true)"
  fi
  normalize_bool "$value" "$default_value"
}

resolve_security_mode() {
  local mode="${SECURITY_MODE:-}"
  if [[ -z "${mode// }" && -f "$CONFIG_PATH" ]]; then
    mode="$(read_product_config_value "$ENVIRONMENT" "operations.security_mode_default" || true)"
  fi
  [[ -z "${mode// }" ]] && mode="secure"
  case "$mode" in
    secure|permissive) ;;
    *)
      echo "Invalid SECURITY_MODE '$mode'. Allowed values: secure|permissive." >&2
      exit 1
      ;;
  esac
  SECURITY_MODE_EFFECTIVE="$mode"
  export SECURITY_MODE="$mode"
}

resolve_execution_contract() {
  EXECUTION_MODE_EFFECTIVE="$(resolve_execution_mode_for_environment "$ENVIRONMENT")"
  if [[ "$EXECUTION_MODE_EFFECTIVE" == "invalid" ]]; then
    echo "Invalid execution mode. Use GLPI_EXECUTION_MODE=local|ssh or EXECUTION_MODE in config/<environment>.env." >&2
    exit 1
  fi
  HOST_ROLE_EFFECTIVE="$(resolve_host_role_for_environment "$ENVIRONMENT")"
  if [[ "$HOST_ROLE_EFFECTIVE" == "invalid" ]]; then
    echo "Invalid host role. Use GLPI_HOST_ROLE=app|db|all or EXECUTION_HOST_ROLE_DEFAULT in config/<environment>.env." >&2
    exit 1
  fi
  if [[ -f "$CONFIG_PATH" ]]; then
    TOPOLOGY_MODE_EFFECTIVE="$(read_product_config_value "$ENVIRONMENT" "topology.mode" || true)"
  else
    TOPOLOGY_MODE_EFFECTIVE="dual-server"
  fi
  [[ -z "${TOPOLOGY_MODE_EFFECTIVE// }" ]] && TOPOLOGY_MODE_EFFECTIVE="dual-server"
  export GLPI_EXECUTION_MODE="$EXECUTION_MODE_EFFECTIVE"
  export GLPI_HOST_ROLE="$HOST_ROLE_EFFECTIVE"
}

resolve_execution_overrides() {
  local assume_db_applied_value=""
  local db_deployment_mode_value=""
  assume_db_applied_value="$(read_product_config_value "$ENVIRONMENT" "OPERATIONS_ASSUME_DB_APPLIED" || true)"
  ASSUME_DB_APPLIED="$(normalize_bool "$assume_db_applied_value" "false")"
  db_deployment_mode_value="$(read_product_config_value "$ENVIRONMENT" "database.deployment_mode" || true)"
  [[ -z "${db_deployment_mode_value// }" ]] && db_deployment_mode_value="self_hosted"
  case "$db_deployment_mode_value" in
    self_hosted|managed) ;;
    *)
      echo "Invalid DATABASE_DEPLOYMENT_MODE '$db_deployment_mode_value'. Allowed values: self_hosted|managed." >&2
      exit 1
      ;;
  esac
  DB_DEPLOYMENT_MODE_EFFECTIVE="$db_deployment_mode_value"
}

require_env_key() {
  local key="$1"
  local purpose="$2"
  local value
  value="$(read_product_config_value "$ENVIRONMENT" "$key" || true)"
  if [[ -z "${value// }" ]]; then
    echo "Missing required config key: $key" >&2
    echo "Purpose: $purpose" >&2
    echo "Used by: deploy apply app runtime rendering and web server/php-fpm configuration" >&2
    exit 1
  fi
  echo "$value"
}

require_runtime_key() {
  local key="$1"
  local purpose="$2"
  local value
  value="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "$key" || true)"
  if [[ -z "${value// }" ]]; then
    echo "Missing required runtime key: $key" >&2
    echo "Purpose: $purpose" >&2
    echo "Source file: $PUBLIC_RUNTIME_PATH" >&2
    exit 1
  fi
  echo "$value"
}

validate_app_runtime_contract() {
  local env_glpi_domain env_app_host env_http_port env_fpm_socket env_install_dir
  local env_web_server_type rt_glpi_domain rt_fpm_socket rt_install_dir rt_http_port rt_web_server_type

  write_step "Validating app configuration contract from config/$ENVIRONMENT.env and runtime files"
  env_glpi_domain="$(require_env_key "GLPI_DOMAIN" "public hostname used by web server virtual host and GLPI URL")"
  env_app_host="$(require_env_key "TOPOLOGY_APP_HOST" "application host endpoint used for IP-based access")"
  env_http_port="$(require_env_key "WEB_HTTP_PORT" "web server listen port for HTTP entrypoint")"
  env_fpm_socket="$(require_env_key "PHP_FPM_SOCKET" "php-fpm socket used by web server fastcgi/handler integration")"
  env_install_dir="$(require_env_key "PATH_GLPI_INSTALL_DIR" "GLPI installation root used by web server document root")"
  env_web_server_type="$(require_env_key "WEB_SERVER_TYPE" "web server selection for app installation (nginx|apache|lighttpd)")"

  rt_glpi_domain="$(require_runtime_key "glpi_domain" "rendered hostname consumed by app role")"
  rt_fpm_socket="$(require_runtime_key "glpi_php_fpm_socket" "rendered php-fpm socket consumed by app role")"
  rt_install_dir="$(require_runtime_key "glpi_install_dir" "rendered GLPI installation root consumed by app role")"
  rt_http_port="$(require_runtime_key "web_http_port" "rendered web HTTP listen port consumed by app role")"
  rt_web_server_type="$(require_runtime_key "glpi_web_server_type" "rendered web server type consumed by app role")"

  [[ "$rt_glpi_domain" == "$env_glpi_domain" ]] || { echo "Runtime mismatch: glpi_domain='$rt_glpi_domain' differs from GLPI_DOMAIN='$env_glpi_domain'." >&2; exit 1; }
  [[ "$rt_fpm_socket" == "$env_fpm_socket" ]] || { echo "Runtime mismatch: glpi_php_fpm_socket='$rt_fpm_socket' differs from PHP_FPM_SOCKET='$env_fpm_socket'." >&2; exit 1; }
  [[ "$rt_install_dir" == "$env_install_dir" ]] || { echo "Runtime mismatch: glpi_install_dir='$rt_install_dir' differs from PATH_GLPI_INSTALL_DIR='$env_install_dir'." >&2; exit 1; }
  [[ "$rt_http_port" == "$env_http_port" ]] || { echo "Runtime mismatch: web_http_port='$rt_http_port' differs from WEB_HTTP_PORT='$env_http_port'." >&2; exit 1; }
  [[ "$rt_web_server_type" == "$env_web_server_type" ]] || { echo "Runtime mismatch: glpi_web_server_type='$rt_web_server_type' differs from WEB_SERVER_TYPE='$env_web_server_type'." >&2; exit 1; }

  echo "Config contract loaded: GLPI_DOMAIN=$env_glpi_domain, TOPOLOGY_APP_HOST=$env_app_host, WEB_HTTP_PORT=$env_http_port, PHP_FPM_SOCKET=$env_fpm_socket, PATH_GLPI_INSTALL_DIR=$env_install_dir, WEB_SERVER_TYPE=$env_web_server_type"
  echo "Runtime contract loaded: glpi_domain=$rt_glpi_domain, glpi_php_fpm_socket=$rt_fpm_socket, glpi_install_dir=$rt_install_dir, web_http_port=$rt_http_port, glpi_web_server_type=$rt_web_server_type"
}

validate_monitoring_runtime_contract() {
  local profile prometheus_enabled grafana_enabled exporter_bind_host grafana_public_mode

  write_step "Validating rendered monitoring configuration contract"

  profile="$(read_effective_runtime_value "monitoring_profile" "minimal")"
  prometheus_enabled="$(read_effective_runtime_value "monitoring_prometheus_enabled" "false")"
  grafana_enabled="$(read_effective_runtime_value "monitoring_grafana_enabled" "false")"
  exporter_bind_host="$(read_effective_runtime_value "monitoring_exporter_bind_host" "127.0.0.1")"
  grafana_public_mode="$(read_effective_runtime_value "monitoring_grafana_public_mode" "disabled")"

  echo "Monitoring contract loaded: profile=$profile, prometheus=$prometheus_enabled, grafana=$grafana_enabled, exporters_bind=$exporter_bind_host, grafana_public_mode=$grafana_public_mode"
}

is_service_active() {
  local service_name="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet "$service_name" 2>/dev/null
    return $?
  fi
  return 1
}

enforce_single_web_server_contract() {
  local selected_type
  selected_type="$(read_product_config_value "$ENVIRONMENT" "WEB_SERVER_TYPE" || true)"
  if [[ -z "${selected_type// }" ]]; then
    echo "Missing required config key: WEB_SERVER_TYPE" >&2
    exit 1
  fi
  selected_type="${selected_type,,}"

  local active_nginx="false" active_apache="false" active_lighttpd="false"
  is_service_active "nginx" && active_nginx="true"
  is_service_active "apache2" && active_apache="true"
  is_service_active "lighttpd" && active_lighttpd="true"

  local conflict_details=""
  case "$selected_type" in
    nginx)
      [[ "$active_apache" == "true" ]] && conflict_details="${conflict_details}apache2 active; "
      [[ "$active_lighttpd" == "true" ]] && conflict_details="${conflict_details}lighttpd active; "
      ;;
    apache)
      [[ "$active_nginx" == "true" ]] && conflict_details="${conflict_details}nginx active; "
      [[ "$active_lighttpd" == "true" ]] && conflict_details="${conflict_details}lighttpd active; "
      ;;
    lighttpd)
      [[ "$active_nginx" == "true" ]] && conflict_details="${conflict_details}nginx active; "
      [[ "$active_apache" == "true" ]] && conflict_details="${conflict_details}apache2 active; "
      ;;
  esac

  if [[ -n "${conflict_details// }" ]]; then
    policy_violation \
      "single-web-server" \
      "WEB_SERVER_TYPE=$selected_type but conflicting web service(s) detected: ${conflict_details}" \
      "Stop/disable non-selected web server services on this host, or switch WEB_SERVER_TYPE to match the active engine."
  fi
}

print_web_engine_postcheck_summary() {
  local selected_type
  selected_type="$(read_product_config_value "$ENVIRONMENT" "WEB_SERVER_TYPE" || true)"
  selected_type="${selected_type,,}"
  [[ -z "${selected_type// }" ]] && selected_type="unknown"

  local nginx_state="inactive" apache_state="inactive" lighttpd_state="inactive"
  is_service_active "nginx" && nginx_state="active"
  is_service_active "apache2" && apache_state="active"
  is_service_active "lighttpd" && lighttpd_state="active"

  local active_list=""
  [[ "$nginx_state" == "active" ]] && active_list="${active_list}nginx,"
  [[ "$apache_state" == "active" ]] && active_list="${active_list}apache,"
  [[ "$lighttpd_state" == "active" ]] && active_list="${active_list}lighttpd,"
  active_list="${active_list%,}"
  [[ -z "${active_list// }" ]] && active_list="none"

  local conflict_list=""
  case "$selected_type" in
    nginx)
      [[ "$apache_state" == "active" ]] && conflict_list="${conflict_list}apache,"
      [[ "$lighttpd_state" == "active" ]] && conflict_list="${conflict_list}lighttpd,"
      ;;
    apache)
      [[ "$nginx_state" == "active" ]] && conflict_list="${conflict_list}nginx,"
      [[ "$lighttpd_state" == "active" ]] && conflict_list="${conflict_list}lighttpd,"
      ;;
    lighttpd)
      [[ "$nginx_state" == "active" ]] && conflict_list="${conflict_list}nginx,"
      [[ "$apache_state" == "active" ]] && conflict_list="${conflict_list}apache,"
      ;;
  esac
  conflict_list="${conflict_list%,}"
  [[ -z "${conflict_list// }" ]] && conflict_list="none"

  echo "Web engine post-check summary:"
  echo "  selected_engine: $selected_type"
  echo "  active_engines: $active_list"
  echo "  nginx_status: $nginx_state"
  echo "  apache_status: $apache_state"
  echo "  lighttpd_status: $lighttpd_state"
  echo "  conflicts: $conflict_list"
}

enforce_local_target_consistency() {
  local domain="$1"
  local action="$2"
  local target="$3"
  if [[ "$EXECUTION_MODE_EFFECTIVE" != "local" ]]; then
    return 0
  fi
  if [[ "$domain" != "deploy" || "$action" != "apply" ]]; then
    return 0
  fi
  case "$target" in
    db)
      if [[ "$HOST_ROLE_EFFECTIVE" != "db" && "$HOST_ROLE_EFFECTIVE" != "all" ]]; then
        echo "Local mode requires GLPI_HOST_ROLE=db|all for deploy apply db." >&2
        exit 1
      fi
      ;;
    app|monitoring|backup)
      if [[ "$HOST_ROLE_EFFECTIVE" != "app" && "$HOST_ROLE_EFFECTIVE" != "all" ]]; then
        echo "Local mode requires GLPI_HOST_ROLE=app|all for deploy apply $target." >&2
        exit 1
      fi
      ;;
    all)
      if [[ "$TOPOLOGY_MODE_EFFECTIVE" == "dual-server" && "$HOST_ROLE_EFFECTIVE" != "all" ]]; then
        echo "Local mode dual-server does not allow deploy apply all with GLPI_HOST_ROLE=$HOST_ROLE_EFFECTIVE." >&2
        echo "Run apply db on DB host and apply app/monitoring/backup on APP host." >&2
        exit 1
      fi
      ;;
  esac
}

enforce_managed_db_target_support() {
  local domain="$1"
  local action="$2"
  local target="$3"

  if ! is_managed_database_mode; then
    return 0
  fi
  if [[ "$domain" != "deploy" ]]; then
    return 0
  fi

  if [[ "$action" == "apply" ]]; then
    case "$target" in
      db|all)
        echo "deploy apply ${target} is not supported when DATABASE_DEPLOYMENT_MODE=managed." >&2
        echo "RDS/managed DB has no Linux DB host for MariaDB provisioning tasks." >&2
        echo "Use deploy apply app|monitoring|backup and validate DB connectivity over TCP." >&2
        exit 1
        ;;
    esac
  fi

  if [[ "$action" == "post-check" && "$target" == "db" ]]; then
    echo "deploy post-check db is not supported when DATABASE_DEPLOYMENT_MODE=managed." >&2
    echo "Use deploy post-check app (or all from APP host) to validate application/runtime checks." >&2
    exit 1
  fi
}

resolve_policy_contract() {
  REQUIRE_TLS="$(read_policy_flag "security.require_tls" "security.require_tls_in_production" "false")"
  REQUIRE_HTTPS="$(read_policy_flag "security.require_https" "security.require_https_in_production" "false")"
  REQUIRE_PROMOTION_GATE="$(read_policy_flag "security.require_promotion_gate" "" "false")"
  REQUIRE_ORDERED_EXECUTION="$(read_policy_flag "security.require_ordered_execution" "" "true")"
}

is_mutating_operation() {
  case "$DOMAIN/$ACTION" in
    deploy/check|deploy/prepare|deploy/apply|deploy/post-check|deploy/rollback|\
    certify/check|certify/prepare|certify/apply|certify/post-check|certify/rollback|certify/run|\
    tls/check|tls/prepare|tls/apply|tls/post-check|tls/rollback|tls/disable|tls/self-signed|tls/install-provided|tls/reload|\
    promote/check|promote/prepare|promote/apply|promote/post-check|promote/rollback|promote/base|promote/app|promote/db|promote/monitoring|promote/backup|promote/all|\
    ops/check|ops/prepare|ops/rollback|ops/users|ops/cert|ops/audit|ops/resume|ops/timezone|\
    email/check|email/prepare|email/install|email/post-check|email/rollback|\
    audit/check|audit/prepare|audit/rollback) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_permissive_justification() {
  if [[ "$SECURITY_MODE_EFFECTIVE" != "permissive" ]]; then
    return 0
  fi
  if [[ -n "${PERMISSIVE_JUSTIFICATION// }" ]]; then
    return 0
  fi
  PERMISSIVE_JUSTIFICATION="$(read_product_config_value "$ENVIRONMENT" "OPERATIONS_PERMISSIVE_JUSTIFICATION" || true)"
  if [[ -z "${PERMISSIVE_JUSTIFICATION// }" ]]; then
    echo "Missing required config key: OPERATIONS_PERMISSIVE_JUSTIFICATION" >&2
    echo "Purpose: mandatory risk acceptance reason for permissive security mode" >&2
    echo "Used by: permissive evidence trail in .runtime/<env>/state and evidence" >&2
    exit 1
  fi
  export SECURITY_JUSTIFICATION="$PERMISSIVE_JUSTIFICATION"
}

persist_permissive_evidence() {
  if [[ "$SECURITY_MODE_EFFECTIVE" != "permissive" ]]; then
    return 0
  fi
  ensure_permissive_justification
  ensure_runtime_foundation "$ENVIRONMENT"

  local operator host now
  operator="$(id -un)"
  host="$(hostname)"
  now="$(date -u +%FT%TZ)"

  {
    echo "---"
    echo "environment: '$(yaml_escape "$ENVIRONMENT")'"
    echo "security_mode: 'permissive'"
    echo "operator: '$(yaml_escape "$operator")'"
    echo "host: '$(yaml_escape "$host")'"
    echo "domain: '$(yaml_escape "$DOMAIN")'"
    echo "action: '$(yaml_escape "$ACTION")'"
    echo "target: '$(yaml_escape "$TARGET")'"
    echo "timestamp_utc: '$now'"
    echo "justification: '$(yaml_escape "$PERMISSIVE_JUSTIFICATION")'"
    echo "violated_policies_count: ${#POLICY_VIOLATIONS[@]}"
    echo "violated_policies:"
    if ((${#POLICY_VIOLATIONS[@]} == 0)); then
      echo "  - id: 'none'"
      echo "    message: 'No policy violation registered in this execution.'"
      echo "    remediation: 'none'"
    else
      local entry id message remediation
      for entry in "${POLICY_VIOLATIONS[@]}"; do
        IFS="|" read -r id message remediation <<<"$entry"
        echo "  - id: '$(yaml_escape "$id")'"
        echo "    message: '$(yaml_escape "$message")'"
        echo "    remediation: '$(yaml_escape "$remediation")'"
      done
    fi
  } >"$PERMISSIVE_EVIDENCE_STATE_PATH"
  cp "$PERMISSIVE_EVIDENCE_STATE_PATH" "$PERMISSIVE_EVIDENCE_REPORT_PATH"
  chmod 600 "$PERMISSIVE_EVIDENCE_STATE_PATH" "$PERMISSIVE_EVIDENCE_REPORT_PATH"
}

policy_violation() {
  local policy_id="$1"
  local message="$2"
  local remediation="${3:-Review policy requirements and rerun.}"
  local warning_message
  if [[ "$SECURITY_MODE_EFFECTIVE" == "secure" ]]; then
    echo "Execution blocked by security policy [$policy_id]: $message" >&2
    echo "Remediation: $remediation" >&2
    exit 1
  fi
  ensure_permissive_justification
  warning_message="permissive mode accepted policy risk [${policy_id}]: ${message}"
  echo "WARNING: ${warning_message}" >&2
  record_execution_warning "$warning_message"
  POLICY_VIOLATIONS+=("${policy_id}|${message}|${remediation}")
  persist_permissive_evidence
}

ensure_deploy_sequence_file() {
  if [[ ! -f "$DEPLOY_SEQUENCE_PATH" ]]; then
    cat >"$DEPLOY_SEQUENCE_PATH" <<'EOF'
---
check_passed: false
db_applied: false
app_applied: false
monitoring_applied: false
backup_applied: false
post_check_passed: false
updated_at: ''
EOF
    chmod 600 "$DEPLOY_SEQUENCE_PATH"
  fi
}

read_deploy_flag() {
  local key="$1"
  local value
  value="$(read_yaml_top_level_value "$DEPLOY_SEQUENCE_PATH" "$key" || true)"
  [[ -z "${value// }" ]] && value="false"
  echo "$value"
}

write_deploy_flag() {
  local key="$1"
  local value="$2"
  update_yaml_top_level_value "$DEPLOY_SEQUENCE_PATH" "$key" "$value"
  update_yaml_top_level_value "$DEPLOY_SEQUENCE_PATH" "updated_at" "$(date -u +%FT%TZ)"
}

require_deploy_flag() {
  local key="$1"
  local human_msg="$2"
  local value
  value="$(read_deploy_flag "$key")"
  if [[ "$value" != "true" ]]; then
    policy_violation "ordered-execution" "$human_msg" "Follow deploy sequence. State file: $DEPLOY_SEQUENCE_PATH"
  fi
}

enforce_apply_sequence() {
  local target="$1"
  if [[ "$REQUIRE_ORDERED_EXECUTION" != "true" ]]; then
    return 0
  fi
  ensure_deploy_sequence_file
  require_deploy_flag "check_passed" "Run deploy check before apply."
  case "$target" in
    db) ;;
    app)
      if is_managed_database_mode; then
        write_step "DATABASE_DEPLOYMENT_MODE=managed: skipping local db_applied prerequisite."
        write_deploy_flag "db_applied" "true"
        return 0
      fi
      if [[ "$EXECUTION_MODE_EFFECTIVE" == "local" && "$TOPOLOGY_MODE_EFFECTIVE" == "dual-server" && "$HOST_ROLE_EFFECTIVE" == "app" && "$ASSUME_DB_APPLIED" == "true" ]]; then
        write_step "Ordered execution override enabled by OPERATIONS_ASSUME_DB_APPLIED=true (local dual-server app host)."
        write_deploy_flag "db_applied" "true"
      else
        require_deploy_flag "db_applied" "Run apply db before apply app."
      fi
      ;;
    monitoring|backup)
      if is_managed_database_mode; then
        write_step "DATABASE_DEPLOYMENT_MODE=managed: skipping local db_applied prerequisite."
        write_deploy_flag "db_applied" "true"
        require_deploy_flag "app_applied" "Run apply app before monitoring/backup."
        return 0
      fi
      require_deploy_flag "db_applied" "Run apply db before monitoring/backup."
      require_deploy_flag "app_applied" "Run apply app before monitoring/backup."
      ;;
    all) ;;
    *) ;;
  esac
}

mark_apply_sequence() {
  local mode="$1"
  local target="$2"
  ensure_deploy_sequence_file
  if [[ "$mode" == "check" ]]; then
    write_deploy_flag "check_passed" "true"
    return 0
  fi
  if [[ "$mode" == "post-check" ]]; then
    write_deploy_flag "post_check_passed" "true"
    return 0
  fi
  case "$target" in
    db) write_deploy_flag "db_applied" "true" ;;
    app) write_deploy_flag "app_applied" "true" ;;
    monitoring) write_deploy_flag "monitoring_applied" "true" ;;
    backup) write_deploy_flag "backup_applied" "true" ;;
    all)
      write_deploy_flag "db_applied" "true"
      write_deploy_flag "app_applied" "true"
      write_deploy_flag "monitoring_applied" "true"
      write_deploy_flag "backup_applied" "true"
      ;;
    *) ;;
  esac
}

enforce_security_policy_contract() {
  local effective_tls_mode="${1:-}"
  local effective_use_tls="${2:-}"

  if [[ -z "${effective_tls_mode// }" ]]; then
    effective_tls_mode="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_mode" || true)"
    [[ -z "${effective_tls_mode// }" ]] && effective_tls_mode="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_mode" || true)"
    [[ -z "${effective_tls_mode// }" ]] && effective_tls_mode="none"
  fi
  if [[ -z "${effective_use_tls// }" ]]; then
    effective_use_tls="false"
    [[ "$effective_tls_mode" != "none" ]] && effective_use_tls="true"
  fi

  if [[ "$REQUIRE_TLS" == "true" && "$effective_tls_mode" != "provided" ]]; then
    policy_violation "require-tls" "Policy requires TLS_MODE=provided, current mode is '$effective_tls_mode'." "Set TLS_MODE=provided or choose secure mode only when compliant."
  fi
  if [[ "$REQUIRE_HTTPS" == "true" && "$effective_use_tls" != "true" ]]; then
    policy_violation "require-https" "Policy requires HTTPS/TLS enabled, current mode '$effective_tls_mode' resolves to HTTP-only." "Enable TLS mode self_signed/provided."
  fi
}

enforce_promotion_gate_policy_if_required() {
  if [[ "$REQUIRE_PROMOTION_GATE" != "true" ]]; then
    return 0
  fi
  if [[ ! -f "$PROMOTION_GATE_PATH" ]]; then
    policy_violation "require-promotion-gate" "Missing promotion gate file: $PROMOTION_GATE_PATH" "Run staging certification or disable SECURITY_REQUIRE_PROMOTION_GATE."
  fi
}

load_managed_db_runtime_contract() {
  if ! is_managed_database_mode; then
    return 1
  fi

  MANAGED_DB_HOST="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_db_host" || true)"
  MANAGED_DB_PORT="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "mariadb_port" || true)"
  MANAGED_DB_NAME="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_db_name" || true)"
  MANAGED_DB_USER="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_db_user" || true)"
  MANAGED_DB_GRANT_HOST="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "db_grant_host" || true)"
  MANAGED_DB_TIMEZONE="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "timezone_name" || true)"
  MANAGED_DB_PASSWORD="$(read_yaml_top_level_value "$SECRET_PATH" "glpi_db_password" || true)"
  MANAGED_DB_ADMIN_PASSWORD="$(read_yaml_top_level_value "$SECRET_PATH" "glpi_db_managed_admin_password" || true)"
  MANAGED_DB_TIMEZONE_SUPPORT_ENABLED="$(normalize_bool "$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_timezone_support_enabled" || true)" "false")"
  MANAGED_DB_TIMEZONE_MODE="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_timezone_db_mode" || true)"
  MANAGED_DB_TIMEZONE_LEGACY_GRANT="$(normalize_bool "$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_timezone_db_legacy_grant" || true)" "false")"

  [[ -z "${MANAGED_DB_PORT// }" ]] && MANAGED_DB_PORT="3306"
  [[ -z "${MANAGED_DB_GRANT_HOST// }" ]] && MANAGED_DB_GRANT_HOST="%"
  [[ -z "${MANAGED_DB_TIMEZONE// }" ]] && MANAGED_DB_TIMEZONE="UTC"
  [[ -z "${MANAGED_DB_TIMEZONE_MODE// }" ]] && MANAGED_DB_TIMEZONE_MODE="disabled"
  MANAGED_DB_TIMEZONE_MODE="${MANAGED_DB_TIMEZONE_MODE,,}"
  case "$MANAGED_DB_TIMEZONE_MODE" in
    disabled|validate|apply) ;;
    *)
      echo "Managed DB validation cannot run: invalid glpi_timezone_db_mode='${MANAGED_DB_TIMEZONE_MODE}'." >&2
      return 1
      ;;
  esac

  if [[ -z "${MANAGED_DB_HOST// }" ]]; then
    echo "Managed DB validation cannot run: missing runtime key glpi_db_host." >&2
    return 1
  fi
  if [[ -z "${MANAGED_DB_USER// }" ]]; then
    echo "Managed DB validation cannot run: missing runtime key glpi_db_user." >&2
    return 1
  fi
  if [[ -z "${MANAGED_DB_NAME// }" ]]; then
    echo "Managed DB validation cannot run: missing runtime key glpi_db_name." >&2
    return 1
  fi
  if [[ -z "${MANAGED_DB_PASSWORD// }" ]]; then
    echo "Managed DB validation cannot run: missing runtime secret glpi_db_password." >&2
    return 1
  fi
  return 0
}

effective_managed_timezone_db_mode() {
  local mode="$MANAGED_DB_TIMEZONE_MODE"
  if [[ "$MANAGED_DB_TIMEZONE_SUPPORT_ENABLED" == "true" && "$mode" == "disabled" ]]; then
    echo "validate"
    return 0
  fi
  echo "$mode"
}

sql_escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

sql_escape_identifier() {
  printf "%s" "$1" | sed 's/`/``/g'
}

run_managed_admin_sql_attempt() {
  local check_label="$1"
  local db_user="$2"
  local db_password="$3"
  local sql_payload="$4"
  local output
  local db_host_escaped db_port_escaped db_user_escaped db_password_escaped sql_escaped

  db_host_escaped="$(shell_escape_single_quotes "$MANAGED_DB_HOST")"
  db_port_escaped="$(shell_escape_single_quotes "$MANAGED_DB_PORT")"
  db_user_escaped="$(shell_escape_single_quotes "$db_user")"
  db_password_escaped="$(shell_escape_single_quotes "$db_password")"
  sql_escaped="$(shell_escape_single_quotes "$sql_payload")"

  if output="$(ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='${db_password_escaped}' mysql --protocol=TCP --host='${db_host_escaped}' --port='${db_port_escaped}' --user='${db_user_escaped}' --batch --skip-column-names --execute='${sql_escaped}'" -o 2>&1)"; then
    echo "Managed DB admin command (${check_label}, user=${db_user}): PASS"
    return 0
  fi

  echo "Managed DB admin command (${check_label}, user=${db_user}): FAIL"
  if [[ -n "${output// }" ]]; then
    echo "  Diagnostic output:"
    printf '%s\n' "$output" | mask_sensitive_stream | mask_managed_db_secret_values_stream | sed 's/^/    /'
  fi
  return 1
}

run_managed_admin_sql() {
  local check_label="$1"
  local sql_payload="$2"

  if [[ -z "${MANAGED_DB_ADMIN_PASSWORD// }" ]]; then
    echo "Managed DB admin command (${check_label}): missing DATABASE_MANAGED_ADMIN_PASSWORD." >&2
    return 1
  fi

  if run_managed_admin_sql_attempt "$check_label" "root" "$MANAGED_DB_ADMIN_PASSWORD" "$sql_payload"; then
    return 0
  fi
  if run_managed_admin_sql_attempt "$check_label" "admin" "$MANAGED_DB_ADMIN_PASSWORD" "$sql_payload"; then
    return 0
  fi
  return 1
}

ensure_managed_db_schema_and_user() {
  local db_name_sql user_sql host_sql password_sql
  local application_grants
  local provision_sql verify_sql

  db_name_sql="$(sql_escape_identifier "$MANAGED_DB_NAME")"
  user_sql="$(sql_escape_literal "$MANAGED_DB_USER")"
  host_sql="$(sql_escape_literal "$MANAGED_DB_GRANT_HOST")"
  password_sql="$(sql_escape_literal "$MANAGED_DB_PASSWORD")"
  application_grants="SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES, LOCK TABLES, CREATE VIEW, SHOW VIEW, TRIGGER, REFERENCES"

  write_step "Ensuring managed DB schema/user/grants for application"
  echo "Managed DB provisioning target: database=${MANAGED_DB_NAME} user=${MANAGED_DB_USER} host=${MANAGED_DB_GRANT_HOST}"
  echo "Managed DB admin users root/admin are used only to provision schema/user/grants."
  echo "Application grant scope: ${application_grants} ON ${MANAGED_DB_NAME}.*"

  provision_sql="CREATE DATABASE IF NOT EXISTS \`${db_name_sql}\`; CREATE USER IF NOT EXISTS '${user_sql}'@'${host_sql}' IDENTIFIED BY '${password_sql}'; ALTER USER '${user_sql}'@'${host_sql}' IDENTIFIED BY '${password_sql}'; REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user_sql}'@'${host_sql}'; GRANT ${application_grants} ON \`${db_name_sql}\`.* TO '${user_sql}'@'${host_sql}'; FLUSH PRIVILEGES;"
  if ! run_managed_admin_sql "provision" "$provision_sql"; then
    echo "Managed DB provisioning skipped: unable to create/alter database user and grant permissions with root/admin." >&2
    echo "Continuing with existing application DB user connectivity validation." >&2
    return 1
  fi

  verify_sql="SHOW GRANTS FOR '${user_sql}'@'${host_sql}';"
  if ! run_managed_admin_sql "verify-grants" "$verify_sql"; then
    echo "Managed DB grant verification skipped: unable to verify grants with root/admin." >&2
    echo "Continuing with existing application DB user connectivity validation." >&2
    return 1
  fi

  return 0
}

run_managed_db_select1_attempt() {
  local check_label="$1"
  local db_user="$2"
  local db_password="$3"
  local db_host_escaped db_port_escaped db_user_escaped db_password_escaped
  local output

  db_host_escaped="$(shell_escape_single_quotes "$MANAGED_DB_HOST")"
  db_port_escaped="$(shell_escape_single_quotes "$MANAGED_DB_PORT")"
  db_user_escaped="$(shell_escape_single_quotes "$db_user")"
  db_password_escaped="$(shell_escape_single_quotes "$db_password")"

  if output="$(ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='${db_password_escaped}' mysql --protocol=TCP --host='${db_host_escaped}' --port='${db_port_escaped}' --user='${db_user_escaped}' --database='$(shell_escape_single_quotes "$MANAGED_DB_NAME")' --execute='SELECT 1;'" -o 2>&1)"; then
    echo "Managed DB connectivity (${check_label}, user=${db_user}): PASS"
    return 0
  fi

  echo "Managed DB connectivity (${check_label}, user=${db_user}): FAIL"
  if [[ -n "${output// }" ]]; then
    echo "  Diagnostic output:"
    printf '%s\n' "$output" | mask_sensitive_stream | sed 's/^/    /'
  fi
  return 1
}

run_managed_db_select1_check() {
  local check_label="$1"
  local fallback_password_available="false"

  if [[ -n "${MANAGED_DB_ADMIN_PASSWORD// }" ]]; then
    fallback_password_available="true"
  fi

  if run_managed_db_select1_attempt "$check_label" "$MANAGED_DB_USER" "$MANAGED_DB_PASSWORD"; then
    return 0
  fi

  if [[ "$fallback_password_available" == "true" ]]; then
    if run_managed_db_select1_attempt "$check_label" "root" "$MANAGED_DB_ADMIN_PASSWORD"; then
      return 0
    fi
    if run_managed_db_select1_attempt "$check_label" "admin" "$MANAGED_DB_ADMIN_PASSWORD"; then
      return 0
    fi
  else
    echo "Managed DB connectivity (${check_label}): skipping root/admin fallback (DATABASE_MANAGED_ADMIN_PASSWORD not configured)."
  fi

  return 1
}

run_managed_db_timezone_check_attempt() {
  local check_label="$1"
  local db_user="$2"
  local db_password="$3"
  local sql_query output
  local db_host_escaped db_port_escaped db_user_escaped db_password_escaped sql_escaped

  db_host_escaped="$(shell_escape_single_quotes "$MANAGED_DB_HOST")"
  db_port_escaped="$(shell_escape_single_quotes "$MANAGED_DB_PORT")"
  db_user_escaped="$(shell_escape_single_quotes "$db_user")"
  db_password_escaped="$(shell_escape_single_quotes "$db_password")"
  sql_query="SELECT CASE WHEN CONVERT_TZ('2000-01-01 00:00:00','UTC','${MANAGED_DB_TIMEZONE}') IS NULL THEN 0 ELSE 1 END AS tz_ready;"
  sql_escaped="$(shell_escape_single_quotes "$sql_query")"

  if output="$(ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='${db_password_escaped}' mysql --protocol=TCP --host='${db_host_escaped}' --port='${db_port_escaped}' --user='${db_user_escaped}' --database='$(shell_escape_single_quotes "$MANAGED_DB_NAME")' --batch --skip-column-names --silent --execute='${sql_escaped}' | grep -qx '1'" -o 2>&1)"; then
    echo "Managed DB timezone readiness (${check_label}, user=${db_user}): PASS"
    return 0
  fi

  echo "Managed DB timezone readiness (${check_label}, user=${db_user}): FAIL"
  if [[ -n "${output// }" ]]; then
    echo "  Diagnostic output:"
    printf '%s\n' "$output" | mask_sensitive_stream | sed 's/^/    /'
  fi
  return 1
}

run_managed_db_timezone_check() {
  local check_label="$1"

  if run_managed_db_timezone_check_attempt "$check_label" "$MANAGED_DB_USER" "$MANAGED_DB_PASSWORD"; then
    return 0
  fi
  if [[ -n "${MANAGED_DB_ADMIN_PASSWORD// }" ]]; then
    if run_managed_db_timezone_check_attempt "$check_label" "root" "$MANAGED_DB_ADMIN_PASSWORD"; then
      return 0
    fi
    if run_managed_db_timezone_check_attempt "$check_label" "admin" "$MANAGED_DB_ADMIN_PASSWORD"; then
      return 0
    fi
  fi
  return 1
}

apply_managed_db_timezone_tables_attempt() {
  local db_user="$1"
  local db_password="$2"
  local output
  local db_host_escaped db_port_escaped db_user_escaped db_password_escaped

  db_host_escaped="$(shell_escape_single_quotes "$MANAGED_DB_HOST")"
  db_port_escaped="$(shell_escape_single_quotes "$MANAGED_DB_PORT")"
  db_user_escaped="$(shell_escape_single_quotes "$db_user")"
  db_password_escaped="$(shell_escape_single_quotes "$db_password")"

  if output="$(ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "set -euo pipefail; tz_loader=\$(command -v mariadb-tzinfo-to-sql || command -v mysql_tzinfo_to_sql || true); if [[ -z \"\$tz_loader\" ]]; then exit 2; fi; \"\$tz_loader\" /usr/share/zoneinfo | MYSQL_PWD='${db_password_escaped}' mysql --protocol=TCP --host='${db_host_escaped}' --port='${db_port_escaped}' --user='${db_user_escaped}' mysql" -o 2>&1)"; then
    return 0
  fi
  if [[ -n "${output// }" ]]; then
    printf '%s\n' "$output" | mask_sensitive_stream | sed 's/^/    /'
  fi
  return 1
}

apply_managed_db_timezone_tables_if_configured() {
  local tz_mode
  tz_mode="$(effective_managed_timezone_db_mode)"

  if [[ "$MANAGED_DB_TIMEZONE_SUPPORT_ENABLED" != "true" ]]; then
    return 0
  fi
  if [[ "$tz_mode" != "apply" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    record_execution_warning "Managed DB timezone apply mode requested but no interactive terminal is available; DB timezone mutation was skipped."
    return 0
  fi
  if [[ -z "${MANAGED_DB_ADMIN_PASSWORD// }" ]]; then
    record_execution_warning "Managed DB timezone apply mode requested but DATABASE_MANAGED_ADMIN_PASSWORD is missing; DB timezone mutation was skipped."
    return 0
  fi
  if ! prompt_yes_no "Managed DB timezone mode is apply. Execute timezone-table load on managed DB now (this may affect other databases in the same instance)?"; then
    record_execution_warning "Operator skipped managed DB timezone-table load."
    return 0
  fi

  write_step "Applying managed DB timezone tables from APP host context"
  if apply_managed_db_timezone_tables_attempt "root" "$MANAGED_DB_ADMIN_PASSWORD"; then
    echo "Managed DB timezone-table load applied using admin user=root."
  elif apply_managed_db_timezone_tables_attempt "admin" "$MANAGED_DB_ADMIN_PASSWORD"; then
    echo "Managed DB timezone-table load applied using admin user=admin."
  else
    record_execution_warning "Managed DB timezone-table load failed for users root/admin."
    return 0
  fi

  if [[ "$MANAGED_DB_TIMEZONE_LEGACY_GRANT" == "true" ]]; then
    local user_sql host_sql grant_sql
    user_sql="$(sql_escape_literal "$MANAGED_DB_USER")"
    host_sql="$(sql_escape_literal "$MANAGED_DB_GRANT_HOST")"
    grant_sql="GRANT SELECT ON mysql.time_zone_name TO '${user_sql}'@'${host_sql}'; FLUSH PRIVILEGES;"
    if run_managed_admin_sql "timezone-legacy-grant" "$grant_sql"; then
      echo "Managed DB timezone legacy grant applied for '${MANAGED_DB_USER}'@'${MANAGED_DB_GRANT_HOST}'."
    else
      record_execution_warning "Managed DB timezone legacy grant failed for '${MANAGED_DB_USER}'@'${MANAGED_DB_GRANT_HOST}'."
    fi
  fi
}

run_managed_db_timezone_validation_gate() {
  local tz_mode
  tz_mode="$(effective_managed_timezone_db_mode)"

  if [[ "$MANAGED_DB_TIMEZONE_SUPPORT_ENABLED" != "true" ]]; then
    echo "Managed DB timezone gate: skipped (GLPI_TIMEZONE_SUPPORT_ENABLED=false)."
    return 0
  fi
  if [[ "$tz_mode" == "disabled" ]]; then
    echo "Managed DB timezone gate: skipped (GLPI_TIMEZONE_DB_MODE=disabled)."
    return 0
  fi

  write_step "Validating managed DB timezone readiness"
  echo "Managed DB timezone mode (effective): ${tz_mode}"
  echo "Managed DB timezone target: ${MANAGED_DB_TIMEZONE}"
  if run_managed_db_timezone_check "initial"; then
    return 0
  fi

  apply_managed_db_timezone_tables_if_configured || true
  write_step "Re-trying managed DB timezone readiness validation"
  if run_managed_db_timezone_check "retry"; then
    return 0
  fi

  record_execution_warning "Managed DB timezone readiness validation failed. Timezone support may be incomplete in the database layer."
  return 0
}

run_managed_db_guided_check() {
  local check_label="$1"
  local check_command="$2"
  local output

  if output="$(ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "$check_command" -o 2>&1)"; then
    echo "  - ${check_label}: PASS"
    return 0
  fi

  echo "  - ${check_label}: FAIL"
  if [[ -n "${output// }" ]]; then
    echo "    diagnostic output:"
    printf '%s\n' "$output" | mask_sensitive_stream | sed 's/^/      /'
  fi
  return 1
}

apply_managed_db_mysql_client_workaround() {
  if [[ ! -t 0 ]]; then
    echo "    workaround: non-interactive mode detected; skipping automatic MySQL client installation."
    return 1
  fi

  if ! prompt_yes_no "Managed DB check detected missing MySQL client on APP host. Apply workaround now (install OS MariaDB/MySQL client package)?"; then
    echo "    workaround: operator skipped automatic MySQL client installation."
    return 1
  fi

  write_step "Applying workaround: installing MySQL client on APP host"
  if ! ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "set -euo pipefail; if command -v apt-get >/dev/null 2>&1; then DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y default-mysql-client; elif command -v dnf >/dev/null 2>&1; then dnf install -y mariadb; elif command -v yum >/dev/null 2>&1; then yum install -y mariadb; else echo 'No supported package manager found (apt, dnf, yum).' >&2; exit 1; fi" -o; then
    echo "Automatic workaround failed: unable to install MySQL client on APP host." >&2
    return 1
  fi

  if run_managed_db_guided_check "MySQL client availability on app host (after workaround)" "command -v mysql >/dev/null 2>&1"; then
    return 0
  fi

  echo "Automatic workaround completed but MySQL client check is still failing." >&2
  return 1
}

run_managed_db_guided_workarounds() {
  local failures=0
  local tcp_check_command
  local dns_check_command

  write_step "Running managed DB guided diagnostics/workarounds"
  echo "Managed DB target: host=${MANAGED_DB_HOST} port=${MANAGED_DB_PORT} user=${MANAGED_DB_USER}"

  if ! run_managed_db_guided_check "MySQL client availability on app host" "command -v mysql >/dev/null 2>&1"; then
    failures=$((failures + 1))
    if apply_managed_db_mysql_client_workaround; then
      failures=$((failures - 1))
    fi
  fi

  dns_check_command="getent hosts '${MANAGED_DB_HOST}' >/dev/null 2>&1"
  if ! run_managed_db_guided_check "DNS resolution for managed DB endpoint" "$dns_check_command"; then
    failures=$((failures + 1))
  fi

  tcp_check_command="timeout 7 bash -lc '</dev/tcp/${MANAGED_DB_HOST}/${MANAGED_DB_PORT}' >/dev/null 2>&1"
  if ! run_managed_db_guided_check "TCP reachability to managed DB endpoint" "$tcp_check_command"; then
    failures=$((failures + 1))
  fi

  if ((failures == 0)); then
    echo "Managed DB guided diagnostics/workarounds completed without blocking findings."
  else
    echo "Managed DB guided diagnostics/workarounds found ${failures} failing checks."
  fi
}

handle_managed_db_validation_after_app_apply() {
  local continue_message

  if ! is_managed_database_mode; then
    return 0
  fi

  if ! load_managed_db_runtime_contract; then
    continue_message="Managed DB runtime contract is incomplete. App deployment succeeded, but DB validation could not run."
    if [[ -n "${MANAGED_DB_HOST// }" ]]; then
      run_managed_db_guided_workarounds || true
    else
      echo "Managed DB endpoint is missing; skipping guided network checks."
    fi
    if [[ -t 0 ]]; then
      if prompt_yes_no "${continue_message} Continue deployment as SUCCESS with warning?"; then
        record_execution_warning "$continue_message"
        return 0
      fi
      echo "Operator selected fail after managed DB runtime contract validation failure." >&2
      return 1
    fi
    record_execution_warning "${continue_message} Continuing as SUCCESS because no interactive terminal is available."
    return 0
  fi

  write_step "Validating managed DB connectivity from APP host (MySQL TCP)"
  echo "Managed DB target: host=${MANAGED_DB_HOST} port=${MANAGED_DB_PORT} user=${MANAGED_DB_USER}"

  if ! ensure_managed_db_schema_and_user; then
    record_execution_warning "Managed DB provisioning/permission check could not run with root/admin; validating existing application DB user instead."
  fi

  if run_managed_db_select1_check "initial"; then
    run_managed_db_timezone_validation_gate
    return 0
  fi

  run_managed_db_guided_workarounds

  write_step "Re-trying managed DB connectivity after guided checks"
  if run_managed_db_select1_check "retry"; then
    run_managed_db_timezone_validation_gate
    return 0
  fi

  continue_message="Managed DB connectivity validation failed after guided checks/retry. App deployment succeeded."
  if [[ -t 0 ]]; then
    if prompt_yes_no "${continue_message} Continue deployment as SUCCESS with warning?"; then
      record_execution_warning "$continue_message"
      return 0
    fi
    echo "Operator selected fail after managed DB connectivity validation failure." >&2
    return 1
  fi

  record_execution_warning "${continue_message} Continuing as SUCCESS because no interactive terminal is available."
  return 0
}

print_operation_log_tail() {
  local log_path
  log_path="$(operation_log_path "$ENVIRONMENT" "$OPERATION_ID")"
  if [[ -f "$log_path" ]]; then
    echo "Last log lines for this execution:" >&2
    tail -n 60 "$log_path" >&2 || true
  fi
}

invoke_ansible_or_fail() {
  local failure_context="$1"
  local environment="$2"
  local tags="$3"
  shift 3

  if invoke_ansible "$environment" "$tags" "$@"; then
    return 0
  fi

  echo "Ansible execution failed during: ${failure_context}" >&2
  echo "Ansible tags: ${tags:-all}" >&2
  print_operation_log_tail
  exit 1
}

ensure_runtime_inputs_if_missing() {
  local include_secrets="${1:-true}"
  write_step "Loading environment config from $CONFIG_PATH"
  require_runtime_file "$CONFIG_PATH" "product configuration file"
  write_step "Rendering runtime files for environment '$ENVIRONMENT'"
  materialize_runtime_from_config "$ENVIRONMENT"
  write_step "Ensuring runtime override file"
  ensure_runtime_override_file "$ENVIRONMENT"
  if [[ "$include_secrets" == "true" ]]; then
    write_step "Ensuring runtime secrets file"
    ensure_secret_keys "$ENVIRONMENT"
  else
    write_step "Skipping secrets prompt for check-only flow"
  fi
  local ssh_key_path
  if [[ "$EXECUTION_MODE_EFFECTIVE" == "ssh" ]]; then
    ssh_key_path="$(read_product_config_value "$ENVIRONMENT" "network.ssh.private_key_path" || true)"
  else
    ssh_key_path=""
  fi
  if [[ -n "${ssh_key_path// }" ]]; then
    ssh_key_path="$(expand_home_path "$ssh_key_path")"
    enforce_ssh_private_key_permissions "$ssh_key_path"
  fi
}

email_read_value() {
  local prompt="$1"
  local reason="$2"
  local target_path="$3"
  local secret="${4:-false}"
  local value=""
  local input_device="/dev/stdin"

  if [[ -r /dev/tty ]]; then
    input_device="/dev/tty"
  fi
  while true; do
    {
      echo "$prompt"
      echo "  Required because: $reason"
      echo "  Will be written to: $target_path"
    } >&2
    if [[ "$secret" == "true" ]]; then
      if [[ "$input_device" != "/dev/tty" ]]; then
        echo "Interactive terminal is required to capture Mailpit secret input securely." >&2
        return 1
      fi
      echo "  Waiting for secure input (hidden)..." >&2
      read -r -s value <"$input_device"
      printf '\n' >&2
    else
      read -r value <"$input_device"
    fi
    if [[ -z "${value// }" ]]; then
      echo "This value is mandatory. Execution will not continue without it." >&2
      continue
    fi
    printf '%s\n' "$value"
    return 0
  done
}

validate_mailpit_auth_username() {
  local username="$1"
  local normalized
  normalized="${username,,}"
  if [[ ! "$username" =~ ^[a-zA-Z0-9._-]{3,64}$ ]]; then
    echo "Mailpit auth username must be 3-64 characters and use only letters, numbers, '.', '_' or '-'." >&2
    return 1
  fi
  case "$normalized" in
    admin|administrator|root|user|test|mailpit|glpi)
      echo "Mailpit auth username '$username' is too common. Use a contextual non-obvious identifier." >&2
      return 1
      ;;
  esac
}

write_mailpit_htpasswd_file() {
  local output_path="$1"
  local purpose="$2"
  local username password hash

  while true; do
    username="$(email_read_value "Mailpit ${purpose} username" "Mailpit ${purpose} access must require explicit authentication." "$output_path")"
    if validate_mailpit_auth_username "$username"; then
      break
    fi
  done
  password="$(email_read_value "Mailpit ${purpose} password" "Mailpit ${purpose} access must use a strong secret." "$output_path" "true")"
  hash="$(printf '%s' "$password" | openssl passwd -apr1 -stdin)"
  ensure_directory "$(dirname "$output_path")"
  printf '%s:%s\n' "$username" "$hash" >"$output_path"
  chmod 600 "$output_path"
}

ensure_email_runtime_auth_files() {
  local prompt_missing="${1:-false}"
  ensure_directory "$EMAIL_AUTH_DIR"
  chmod 700 "$EMAIL_RUNTIME_DIR" "$EMAIL_AUTH_DIR" >/dev/null 2>&1 || true
  if [[ -s "$EMAIL_UI_AUTH_FILE" && -s "$EMAIL_SMTP_AUTH_FILE" ]]; then
    return 0
  fi
  if [[ "$prompt_missing" != "true" ]]; then
    echo "Missing Mailpit runtime auth files." >&2
    echo "Run './scripts/glpictl.sh $ENVIRONMENT email prepare mailpit' before install." >&2
    echo "Expected files:" >&2
    echo "  $EMAIL_UI_AUTH_FILE" >&2
    echo "  $EMAIL_SMTP_AUTH_FILE" >&2
    exit 1
  fi
  assert_command "openssl"
  [[ -s "$EMAIL_UI_AUTH_FILE" ]] || write_mailpit_htpasswd_file "$EMAIL_UI_AUTH_FILE" "UI"
  [[ -s "$EMAIL_SMTP_AUTH_FILE" ]] || write_mailpit_htpasswd_file "$EMAIL_SMTP_AUTH_FILE" "SMTP"
}

email_mailpit_access_url() {
  local tls_mode glpi_domain http_port https_port scheme port path url
  tls_mode="$(read_effective_runtime_value "glpi_tls_mode" "none")"
  glpi_domain="$(read_effective_runtime_value "glpi_domain" "unknown-host")"
  http_port="$(read_effective_runtime_value "web_http_port" "80")"
  https_port="$(read_effective_runtime_value "web_https_port" "443")"
  path="$(read_effective_runtime_value "email_mailpit_ui_path" "/mailpit")"
  if [[ "$tls_mode" == "none" ]]; then
    scheme="http"
    port="$http_port"
  else
    scheme="https"
    port="$https_port"
  fi
  url="${scheme}://${glpi_domain}"
  if [[ "$scheme" == "http" && "$port" != "80" ]]; then
    url="${url}:${port}"
  fi
  if [[ "$scheme" == "https" && "$port" != "443" ]]; then
    url="${url}:${port}"
  fi
  printf '%s%s\n' "$url" "$path"
}

write_email_runtime_vars() {
  local action_name="$1"
  local access_url
  ensure_directory "$EMAIL_RUNTIME_DIR"
  chmod 700 "$EMAIL_RUNTIME_DIR" >/dev/null 2>&1 || true
  access_url="$(email_mailpit_access_url)"
  save_yaml_map "$EMAIL_RUNTIME_PATH" \
    email_mailpit_action "$action_name" \
    email_mailpit_local_ui_auth_file "$EMAIL_UI_AUTH_FILE" \
    email_mailpit_local_smtp_auth_file "$EMAIL_SMTP_AUTH_FILE" \
    email_mailpit_access_url "$access_url"
}

require_mailpit_enabled() {
  local enabled
  enabled="$(read_effective_runtime_value "email_mailpit_enabled" "false")"
  enabled="$(normalize_bool "$enabled" "false")"
  if [[ "$enabled" != "true" ]]; then
    echo "Mailpit email service is disabled for this environment." >&2
    echo "Set EMAIL_MAILPIT_ENABLED=true in config/$ENVIRONMENT.env and rerun." >&2
    exit 1
  fi
}

print_email_mailpit_summary() {
  local access_url smtp_host smtp_port
  access_url="$(email_mailpit_access_url)"
  smtp_host="$(read_effective_runtime_value "email_mailpit_smtp_bind_host" "127.0.0.1")"
  smtp_port="$(read_effective_runtime_value "email_mailpit_smtp_port" "1025")"
  echo "Mailpit access summary:"
  echo "  ui_url: $access_url"
  echo "  smtp_host: $smtp_host"
  echo "  smtp_port: $smtp_port"
  echo "  smtp_starttls_required: true"
  echo "  glpi_smtp_auto_configured: false"
}

run_deploy() {
  local mode="$1"
  local target="$2"
  local post_check_tags="app,db"
  local run_as_deploy_domain="false"
  local backup_dir notes

  [[ "$DOMAIN" == "deploy" ]] && run_as_deploy_domain="true"
  enforce_managed_db_target_support "deploy" "$mode" "$target"
  enforce_local_target_consistency "deploy" "$mode" "$target"

  case "$mode" in
    check|prepare|apply|post-check|rollback) ;;
    *)
      echo "Unsupported deploy action: $mode (expected check|prepare|apply|post-check|rollback)" >&2
      exit 1
      ;;
  esac

  if [[ "$run_as_deploy_domain" == "true" ]]; then
    case "$mode" in
      check|prepare|apply|post-check|rollback)
        create_domain_backup_snapshot "deploy" "$mode"
        ;;
    esac
  fi

  if [[ "$mode" == "rollback" ]]; then
    if [[ "$run_as_deploy_domain" != "true" ]]; then
      echo "Deploy rollback is only supported through deploy domain entrypoint." >&2
      exit 1
    fi
    backup_dir="$(find_domain_backup_for_restore "deploy" "true")"
    restore_remote_domain_backup_snapshot "deploy" "$backup_dir"
    run_domain_metadata_restore_from_backup "deploy" "$backup_dir"
    notes="Deploy rollback restored remote/local runtime/config/evidence/sequence metadata from backup=${backup_dir}."
    write_domain_state "deploy" "rollback" "completed" "$notes"
    write_domain_evidence_simple "deploy" "rollback" "pass" "$notes"
    echo "Deploy action '$mode' completed."
    return 0
  fi

  if [[ "$mode" == "check" ]]; then
    ensure_runtime_inputs_if_missing "false"
  else
    ensure_runtime_inputs_if_missing "true"
  fi
  resolve_policy_contract
  if [[ "$mode" != "check" ]]; then
    enforce_promotion_gate_policy_if_required
    enforce_security_policy_contract
  fi
  export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"

  if [[ "$mode" == "check" ]]; then
    case "$target" in
      app|all) enforce_single_web_server_contract ;;
    esac
    case "$target" in
      monitoring|all) validate_monitoring_runtime_contract ;;
    esac
    write_step "Validating rendered Ansible inventory"
    ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
    mark_apply_sequence "$mode" "$target"
    if [[ "$run_as_deploy_domain" == "true" ]]; then
      notes="Deploy check completed. No mutable system changes were applied."
      write_domain_state "deploy" "check" "completed" "$notes"
      write_domain_evidence_simple "deploy" "check" "pass" "$notes"
    fi
    echo "Check completed successfully."
    return 0
  fi

  if [[ "$mode" == "prepare" ]]; then
    case "$target" in
      app|all) enforce_single_web_server_contract ;;
    esac
    case "$target" in
      monitoring|all) validate_monitoring_runtime_contract ;;
    esac
    write_step "Validating rendered Ansible inventory"
    ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
    if [[ "$run_as_deploy_domain" == "true" ]]; then
      notes="Deploy prepare completed. Runtime and inventory were prepared without invoking mutable deployment tasks."
      write_domain_state "deploy" "prepare" "completed" "$notes"
      write_domain_evidence_simple "deploy" "prepare" "pass" "$notes"
    fi
    echo "Deploy action '$mode' completed."
    return 0
  fi

  if [[ "$mode" == "apply" ]]; then
    case "$target" in
      app|all)
        validate_app_runtime_contract
        enforce_single_web_server_contract
        ;;
    esac
    case "$target" in
      monitoring|all) validate_monitoring_runtime_contract ;;
    esac
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
    apply)
      enforce_apply_sequence "$target"
      if [[ "$run_as_deploy_domain" == "true" ]]; then
        create_remote_domain_backup_snapshot "deploy" "apply" "$target" "$SCOPE"
      fi
      if is_managed_database_mode && [[ "$target" == "app" ]]; then
        write_step "Stage 1/2 (managed): applying application deployment (hard gate)"
      fi
      invoke_ansible_or_fail "deploy ${mode} ${target}" "$ENVIRONMENT" "$tags" "${extra_var_files[@]}"
      if is_managed_database_mode && [[ "$target" == "app" || "$target" == "all" ]]; then
        write_step "Stage 2/2 (managed): validating managed DB connectivity (controlled gate)"
        if ! handle_managed_db_validation_after_app_apply; then
          exit 1
        fi
      fi
      mark_apply_sequence "$mode" "$target"
      ;;
    post-check)
      if [[ "$REQUIRE_ORDERED_EXECUTION" == "true" ]]; then
        if ! is_managed_database_mode; then
          require_deploy_flag "db_applied" "Run apply db before post-check."
        fi
        require_deploy_flag "app_applied" "Run apply app before post-check."
      fi
      case "$target" in
        app|db) post_check_tags="$target" ;;
        all)
          if is_managed_database_mode; then
            post_check_tags="app"
          fi
          if [[ "$EXECUTION_MODE_EFFECTIVE" == "local" && "$TOPOLOGY_MODE_EFFECTIVE" == "dual-server" ]]; then
            if [[ "$HOST_ROLE_EFFECTIVE" == "app" ]]; then
              post_check_tags="app"
            elif [[ "$HOST_ROLE_EFFECTIVE" == "db" ]]; then
              if ! is_managed_database_mode; then
                post_check_tags="db"
              fi
            fi
          fi
          ;;
        *)
          echo "Unsupported post-check target: $target (expected app|db|all)" >&2
          exit 1
          ;;
      esac
      invoke_ansible_or_fail "deploy ${mode} ${target}" "$ENVIRONMENT" "$post_check_tags" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH"
      if [[ "$target" == "app" || "$target" == "all" ]]; then
        print_web_engine_postcheck_summary
      fi
      mark_apply_sequence "$mode" "$target"
      ;;
    *)
      echo "Unsupported deploy action: $mode (expected check|prepare|apply|post-check|rollback)" >&2
      exit 1
      ;;
  esac

  if [[ "$run_as_deploy_domain" == "true" ]]; then
    notes="Deploy ${mode} completed for target=${target}."
    write_domain_state "deploy" "$mode" "completed" "$notes"
    write_domain_evidence_simple "deploy" "$mode" "pass" "$notes"
  fi
}

run_certify() {
  local certify_action="$ACTION"
  local notes backup_dir

  if [[ "$ENVIRONMENT" != "staging" ]]; then
    echo "Certification is only supported for staging." >&2
    exit 1
  fi

  case "$certify_action" in
    check|prepare|apply|post-check|rollback|run) ;;
    *)
      echo "Unsupported certify action: $certify_action (expected check|prepare|apply|post-check|rollback|run)" >&2
      exit 1
      ;;
  esac

  if [[ "$certify_action" == "run" ]]; then
    certify_action="apply"
  fi

  case "$certify_action" in
    check)
      create_domain_backup_snapshot "certify" "check"
      ensure_runtime_inputs_if_missing "false"
      ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
      notes="Certify check completed. Runtime and inventory validations passed."
      write_domain_state "certify" "check" "completed" "$notes"
      write_domain_evidence_simple "certify" "check" "pass" "$notes"
      ;;
    prepare)
      create_domain_backup_snapshot "certify" "prepare"
      ensure_runtime_inputs_if_missing "false"
      ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
      notes="Certify prepare completed. Local runtime/evidence/state snapshot is ready."
      write_domain_state "certify" "prepare" "completed" "$notes"
      write_domain_evidence_simple "certify" "prepare" "pass" "$notes"
      ;;
    apply)
      create_domain_backup_snapshot "certify" "apply"
      bash "$SCRIPT_ROOT/certify-staging.sh"
      notes="Certify apply completed. Staging certification workflow executed."
      write_domain_state "certify" "apply" "completed" "$notes"
      write_domain_evidence_simple "certify" "apply" "pass" "$notes"
      ;;
    post-check)
      create_domain_backup_snapshot "certify" "post-check"
      if [[ ! -f "$PROMOTION_GATE_PATH" ]]; then
        echo "Certification post-check failed: promotion gate file not found at $PROMOTION_GATE_PATH." >&2
        exit 1
      fi
      notes="Certify post-check completed. Promotion gate file is present."
      write_domain_state "certify" "post-check" "completed" "$notes"
      write_domain_evidence_simple "certify" "post-check" "pass" "$notes"
      ;;
    rollback)
      create_domain_backup_snapshot "certify" "rollback"
      backup_dir="$(find_domain_backup_for_restore "certify" "true")"
      run_domain_metadata_restore_from_backup "certify" "$backup_dir"
      notes="Certify rollback restored local runtime/config/evidence/state and promotion gate metadata from backup=${backup_dir}."
      write_domain_state "certify" "rollback" "completed" "$notes"
      write_domain_evidence_simple "certify" "rollback" "pass" "$notes"
      ;;
  esac
}

resolve_tls_apply_action_from_target() {
  local target="${1:-}"
  local normalized configured_mode
  normalized="${target,,}"
  if [[ -z "${normalized// }" || "$normalized" == "all" ]]; then
    configured_mode="$(read_product_config_value "$ENVIRONMENT" "tls.mode" || true)"
    [[ -z "${configured_mode// }" ]] && configured_mode="$(read_effective_runtime_value "glpi_tls_mode" "none")"
    normalized="${configured_mode,,}"
  fi
  case "$normalized" in
    none|disable) echo "disable" ;;
    self_signed|self-signed|selfsigned) echo "self-signed" ;;
    provided|install-provided|install_provided) echo "install-provided" ;;
    reload) echo "reload" ;;
    *)
      echo "Unsupported TLS apply target: $target (expected none|self-signed|provided)." >&2
      exit 1
      ;;
  esac
}

resolve_tls_payload_for_legacy_action() {
  local tls_action="$1"
  local local_cert_path="" local_key_path="" tls_mode="none"
  case "$tls_action" in
    disable) tls_mode="none" ;;
    self-signed) tls_mode="self_signed" ;;
    install-provided)
      tls_mode="provided"
      local_cert_path="$(read_product_config_value "$ENVIRONMENT" "TLS_PROVIDED_LOCAL_CERT_PATH" || true)"
      local_key_path="$(read_product_config_value "$ENVIRONMENT" "TLS_PROVIDED_LOCAL_KEY_PATH" || true)"
      local_cert_path="$(expand_home_path "$local_cert_path")"
      local_key_path="$(expand_home_path "$local_key_path")"
      if [[ -z "${local_cert_path// }" || ! -f "$local_cert_path" ]]; then
        echo "Missing or invalid TLS_PROVIDED_LOCAL_CERT_PATH in config/$ENVIRONMENT.env" >&2
        exit 1
      fi
      if [[ -z "${local_key_path// }" || ! -f "$local_key_path" ]]; then
        echo "Missing or invalid TLS_PROVIDED_LOCAL_KEY_PATH in config/$ENVIRONMENT.env" >&2
        exit 1
      fi
      ;;
    reload)
      tls_mode="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_mode" || true)"
      [[ -z "${tls_mode// }" ]] && tls_mode="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_mode" || true)"
      [[ -z "${tls_mode// }" ]] && tls_mode="none"
      local_cert_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" || true)"
      [[ -z "${local_cert_path// }" ]] && local_cert_path="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" || true)"
      local_key_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_key_path" || true)"
      [[ -z "${local_key_path// }" ]] && local_key_path="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_provided_local_key_path" || true)"
      ;;
    *)
      echo "Unsupported TLS legacy action: $tls_action (expected disable|self-signed|install-provided|reload)." >&2
      exit 1
      ;;
  esac
  printf "%s\n%s\n%s\n" "$tls_mode" "$local_cert_path" "$local_key_path"
}

execute_tls_legacy_apply() {
  local tls_action="$1"
  local domain local_cert_path local_key_path tls_mode use_tls
  local -a payload
  mapfile -t payload < <(resolve_tls_payload_for_legacy_action "$tls_action")
  tls_mode="${payload[0]:-none}"
  local_cert_path="${payload[1]:-}"
  local_key_path="${payload[2]:-}"
  domain="$(read_effective_runtime_value "glpi_domain" "")"
  [[ -z "${domain// }" ]] && domain="$(read_product_config_value "$ENVIRONMENT" "glpi.domain" || true)"
  use_tls="false"
  [[ "$tls_mode" != "none" ]] && use_tls="true"
  enforce_security_policy_contract "$tls_mode" "$use_tls"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_mode" "$tls_mode"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_use_tls" "$use_tls"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_common_name" "$domain"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" "$local_cert_path"
  update_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_key_path" "$local_key_path"
  export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
  invoke_ansible "$ENVIRONMENT" "app" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH"
}

run_tls_web_server_postcheck() {
  local web_server_type postcheck_cmd
  web_server_type="$(read_effective_runtime_value "glpi_web_server_type" "nginx")"
  web_server_type="${web_server_type,,}"
  case "$web_server_type" in
    nginx)
      postcheck_cmd="nginx -t"
      ;;
    apache)
      postcheck_cmd="if command -v apache2ctl >/dev/null 2>&1; then apache2ctl -t; elif command -v httpd >/dev/null 2>&1; then httpd -t; else exit 1; fi"
      ;;
    lighttpd)
      postcheck_cmd="lighttpd -tt -f /etc/lighttpd/lighttpd.conf"
      ;;
    *)
      return 0
      ;;
  esac
  export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
  ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -m shell -a "$postcheck_cmd" -o >/dev/null
}

run_tls() {
  local tls_action="$ACTION"
  local tls_target="$TARGET"
  local effective_tls_mode use_tls legacy_action notes backup_dir

  case "$tls_action" in
    check|prepare|apply|post-check|rollback|disable|self-signed|install-provided|reload) ;;
    *)
      echo "Unsupported TLS action: $tls_action (expected check|prepare|apply|post-check|rollback|disable|self-signed|install-provided|reload)" >&2
      exit 1
      ;;
  esac
  resolve_policy_contract

  case "$tls_action" in
    check)
      create_domain_backup_snapshot "tls" "check"
      ensure_runtime_inputs_if_missing "false"
      effective_tls_mode="$(read_effective_runtime_value "glpi_tls_mode" "none")"
      use_tls="false"
      [[ "$effective_tls_mode" != "none" ]] && use_tls="true"
      enforce_security_policy_contract "$effective_tls_mode" "$use_tls"
      notes="TLS check completed. Current mode=${effective_tls_mode}. No mutable changes were applied."
      write_domain_state "tls" "check" "completed" "$notes"
      write_domain_evidence_simple "tls" "check" "pass" "$notes"
      echo "TLS action '$tls_action' completed."
      return
      ;;
    prepare)
      create_domain_backup_snapshot "tls" "prepare"
      ensure_runtime_inputs_if_missing "false"
      legacy_action="$(resolve_tls_apply_action_from_target "$tls_target")"
      resolve_tls_payload_for_legacy_action "$legacy_action" >/dev/null
      notes="TLS prepare completed. Requested target=${tls_target}, mapped_action=${legacy_action}. Runtime preparation only."
      write_domain_state "tls" "prepare" "completed" "$notes"
      write_domain_evidence_simple "tls" "prepare" "pass" "$notes"
      echo "TLS action '$tls_action' completed."
      return
      ;;
    apply)
      create_domain_backup_snapshot "tls" "apply"
      ensure_runtime_inputs_if_missing "true"
      legacy_action="$(resolve_tls_apply_action_from_target "$tls_target")"
      create_remote_domain_backup_snapshot "tls" "apply" "$legacy_action" "$SCOPE"
      execute_tls_legacy_apply "$legacy_action"
      run_tls_web_server_postcheck
      notes="TLS apply completed. Requested target=${tls_target}, mapped_action=${legacy_action}."
      write_domain_state "tls" "apply" "completed" "$notes"
      write_domain_evidence_simple "tls" "apply" "pass" "$notes"
      echo "TLS action '$tls_action' completed."
      return
      ;;
    post-check)
      create_domain_backup_snapshot "tls" "post-check"
      ensure_runtime_inputs_if_missing "false"
      effective_tls_mode="$(read_effective_runtime_value "glpi_tls_mode" "none")"
      use_tls="false"
      [[ "$effective_tls_mode" != "none" ]] && use_tls="true"
      enforce_security_policy_contract "$effective_tls_mode" "$use_tls"
      run_tls_web_server_postcheck
      notes="TLS post-check completed. Mode=${effective_tls_mode}, use_tls=${use_tls}."
      write_domain_state "tls" "post-check" "completed" "$notes"
      write_domain_evidence_simple "tls" "post-check" "pass" "$notes"
      echo "TLS action '$tls_action' completed."
      return
      ;;
    rollback)
      create_domain_backup_snapshot "tls" "rollback"
      backup_dir="$(find_domain_backup_for_restore "tls" "true")"
      restore_remote_domain_backup_snapshot "tls" "$backup_dir"
      run_domain_metadata_restore_from_backup "tls" "$backup_dir"
      notes="TLS rollback restored remote/local runtime/evidence/state from backup=${backup_dir}."
      write_domain_state "tls" "rollback" "completed" "$notes"
      write_domain_evidence_simple "tls" "rollback" "pass" "$notes"
      echo "TLS action '$tls_action' completed."
      return
      ;;
    disable|self-signed|install-provided|reload)
      create_domain_backup_snapshot "tls" "$tls_action"
      ensure_runtime_inputs_if_missing "true"
      create_remote_domain_backup_snapshot "tls" "$tls_action" "$TARGET" "$SCOPE"
      execute_tls_legacy_apply "$tls_action"
      run_tls_web_server_postcheck
      notes="TLS legacy action completed using action=${tls_action}."
      write_domain_state "tls" "$tls_action" "completed" "$notes"
      write_domain_evidence_simple "tls" "$tls_action" "pass" "$notes"
      echo "TLS action '$tls_action' completed."
      return
      ;;
  esac
}

run_ops() {
  local backup_dir users_action users_scope notes
  resolve_policy_contract
  enforce_security_policy_contract

  case "$ACTION" in
    check)
      create_domain_backup_snapshot "ops" "check"
      bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
      notes="Ops check alias completed via audit check."
      write_domain_state "ops" "check" "completed" "$notes"
      write_domain_evidence_simple "ops" "check" "pass" "$notes"
      return
      ;;
    prepare)
      create_domain_backup_snapshot "ops" "prepare"
      notes="Ops prepare completed. Local runtime/evidence/state snapshot is ready."
      write_domain_state "ops" "prepare" "completed" "$notes"
      write_domain_evidence_simple "ops" "prepare" "pass" "$notes"
      return
      ;;
    rollback)
      create_domain_backup_snapshot "ops" "rollback"
      backup_dir="$(find_domain_backup_for_restore "ops" "true")"
      restore_remote_domain_backup_snapshot "ops" "$backup_dir"
      run_domain_metadata_restore_from_backup "ops" "$backup_dir"
      notes="Ops rollback restored remote/local runtime/evidence/state from backup=${backup_dir}."
      write_domain_state "ops" "rollback" "completed" "$notes"
      write_domain_evidence_simple "ops" "rollback" "pass" "$notes"
      return
      ;;
    users)
      create_domain_backup_snapshot "ops" "users"
      users_action="$TARGET"
      users_scope="${SCOPE:-os}"
      if is_managed_database_mode && [[ "$users_scope" == "db" ]]; then
        echo "ops users <action> db is not supported when DATABASE_DEPLOYMENT_MODE=managed." >&2
        echo "Use the RDS/database administration workflow for DB user lifecycle operations." >&2
        exit 1
      fi
      ensure_runtime_inputs_if_missing "true"
      create_remote_domain_backup_snapshot "ops" "users" "$users_action" "$users_scope"
      bash "$SCRIPT_ROOT/ops-maintenance.sh" users "$ENVIRONMENT" "$users_action" "$users_scope"
      return
      ;;
    cert)
      create_domain_backup_snapshot "ops" "cert"
      ensure_runtime_inputs_if_missing "true"
      create_remote_domain_backup_snapshot "ops" "cert" "$TARGET" "$SCOPE"
      bash "$SCRIPT_ROOT/ops-maintenance.sh" cert "$ENVIRONMENT" "$TARGET"
      return
      ;;
    audit)
      create_domain_backup_snapshot "ops" "audit"
      bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
      return
      ;;
    resume)
      create_domain_backup_snapshot "ops" "resume"
      ensure_runtime_inputs_if_missing "true"
      create_remote_domain_backup_snapshot "ops" "resume" "$TARGET" "$SCOPE"
      bash "$SCRIPT_ROOT/ops-maintenance.sh" resume "$ENVIRONMENT"
      return
      ;;
    timezone)
      create_domain_backup_snapshot "ops" "timezone"
      local timezone_action
      timezone_action="${TARGET:-check}"
      case "$timezone_action" in
        check|apply) ;;
        *)
          echo "Unsupported ops timezone action: ${timezone_action} (expected check|apply)" >&2
          exit 1
          ;;
      esac
      ensure_runtime_inputs_if_missing "true"
      if [[ "$timezone_action" == "apply" ]]; then
        create_remote_domain_backup_snapshot "ops" "timezone" "$timezone_action" "$SCOPE"
      fi
      bash "$SCRIPT_ROOT/ops-maintenance.sh" timezone "$ENVIRONMENT" "$timezone_action"
      return
      ;;
    *)
      echo "Unsupported ops action: $ACTION (expected check|prepare|rollback|users|cert|audit|resume|timezone)" >&2
      exit 1
      ;;
  esac
}

run_email() {
  local email_action="$ACTION"
  local email_target="$TARGET"
  local notes

  [[ -z "${email_target// }" || "$email_target" == "all" ]] && email_target="mailpit"
  if [[ "$email_target" != "mailpit" ]]; then
    echo "Unsupported email target: $email_target (expected mailpit)" >&2
    exit 1
  fi
  case "$email_action" in
    check|prepare|install|post-check|rollback) ;;
    *)
      echo "Unsupported email action: $email_action (expected check|prepare|install|post-check|rollback)" >&2
      exit 1
      ;;
  esac

  create_domain_backup_snapshot "email" "$email_action"
  resolve_policy_contract
  ensure_runtime_inputs_if_missing "false"
  case "$email_action" in
    check|install|post-check) enforce_security_policy_contract ;;
  esac

  case "$email_action" in
    check)
      write_email_runtime_vars "check"
      export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
      invoke_ansible_or_fail "email check mailpit" "$ENVIRONMENT" "email" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$EMAIL_RUNTIME_PATH"
      notes="Email check completed for Mailpit. No mutable system changes were applied."
      write_domain_state "email" "check" "completed" "$notes"
      write_domain_evidence_simple "email" "check" "pass" "$notes"
      print_email_mailpit_summary
      ;;
    prepare)
      require_mailpit_enabled
      ensure_email_runtime_auth_files "true"
      write_email_runtime_vars "check"
      notes="Email prepare completed for Mailpit. Runtime auth files were prepared under .runtime/${ENVIRONMENT}/email."
      write_domain_state "email" "prepare" "completed" "$notes"
      write_domain_evidence_simple "email" "prepare" "pass" "$notes"
      echo "Mailpit runtime auth files prepared."
      ;;
    install)
      require_mailpit_enabled
      enforce_promotion_gate_policy_if_required
      ensure_email_runtime_auth_files "false"
      write_email_runtime_vars "install"
      create_remote_domain_backup_snapshot "email" "install" "mailpit" "$SCOPE"
      export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
      invoke_ansible_or_fail "email install mailpit" "$ENVIRONMENT" "email" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$EMAIL_RUNTIME_PATH"
      notes="Email install completed for Mailpit."
      write_domain_state "email" "install" "completed" "$notes"
      write_domain_evidence_simple "email" "install" "pass" "$notes"
      print_email_mailpit_summary
      ;;
    post-check)
      require_mailpit_enabled
      write_email_runtime_vars "post-check"
      export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
      invoke_ansible_or_fail "email post-check mailpit" "$ENVIRONMENT" "email" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$EMAIL_RUNTIME_PATH"
      notes="Email post-check completed for Mailpit."
      write_domain_state "email" "post-check" "completed" "$notes"
      write_domain_evidence_simple "email" "post-check" "pass" "$notes"
      print_email_mailpit_summary
      ;;
    rollback)
      write_email_runtime_vars "rollback"
      create_remote_domain_backup_snapshot "email" "rollback" "mailpit" "$SCOPE"
      export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"
      invoke_ansible_or_fail "email rollback mailpit" "$ENVIRONMENT" "email" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$EMAIL_RUNTIME_PATH"
      notes="Email rollback completed for Mailpit. Compose service and proxy blocks were removed; captured data/auth files were preserved."
      write_domain_state "email" "rollback" "completed" "$notes"
      write_domain_evidence_simple "email" "rollback" "pass" "$notes"
      ;;
  esac
}

run_audit() {
  local audit_action="$ACTION"
  local notes backup_dir

  case "$audit_action" in
    check)
      create_domain_backup_snapshot "audit" "check"
      bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
      notes="Audit check completed."
      write_domain_state "audit" "check" "completed" "$notes"
      write_domain_evidence_simple "audit" "check" "pass" "$notes"
      ;;
    prepare)
      create_domain_backup_snapshot "audit" "prepare"
      notes="Audit prepare completed. Local runtime/evidence/state snapshot is ready."
      write_domain_state "audit" "prepare" "completed" "$notes"
      write_domain_evidence_simple "audit" "prepare" "pass" "$notes"
      ;;
    rollback)
      create_domain_backup_snapshot "audit" "rollback"
      backup_dir="$(find_domain_backup_for_restore "audit" "true")"
      run_domain_metadata_restore_from_backup "audit" "$backup_dir"
      notes="Audit rollback restored local runtime/evidence/state from backup=${backup_dir}."
      write_domain_state "audit" "rollback" "completed" "$notes"
      write_domain_evidence_simple "audit" "rollback" "pass" "$notes"
      ;;
    *)
      echo "Unsupported audit action: $audit_action (expected check|prepare|rollback)" >&2
      exit 1
      ;;
  esac
}

run_promote_legacy_apply() {
  local promote_target="$1"
  resolve_policy_contract
  enforce_promotion_gate_policy_if_required
  run_deploy apply "$promote_target"
}

run_promote() {
  local promote_action="$ACTION"
  local promote_target="$TARGET"
  local notes backup_dir

  case "$promote_action" in
    check|prepare|apply|post-check|rollback) ;;
    *)
      case "$promote_action" in
        base|app|db|monitoring|backup|all)
          promote_target="$promote_action"
          ;;
      esac
      promote_action="apply"
      ;;
  esac

  case "$promote_action" in
    check)
      create_domain_backup_snapshot "promote" "check"
      ensure_runtime_inputs_if_missing "false"
      resolve_policy_contract
      enforce_security_policy_contract
      enforce_promotion_gate_policy_if_required
      ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
      notes="Promote check completed. Inventory and promotion gate validations passed."
      write_domain_state "promote" "check" "completed" "$notes"
      write_domain_evidence_simple "promote" "check" "pass" "$notes"
      ;;
    prepare)
      create_domain_backup_snapshot "promote" "prepare"
      ensure_runtime_inputs_if_missing "false"
      resolve_policy_contract
      enforce_security_policy_contract
      enforce_promotion_gate_policy_if_required
      notes="Promote prepare completed. Local metadata snapshot created before promotion apply."
      write_domain_state "promote" "prepare" "completed" "$notes"
      write_domain_evidence_simple "promote" "prepare" "pass" "$notes"
      ;;
    apply)
      create_domain_backup_snapshot "promote" "apply"
      ensure_runtime_inputs_if_missing "true"
      enforce_managed_db_target_support "deploy" "apply" "$promote_target"
      create_remote_domain_backup_snapshot "promote" "apply" "$promote_target" "$SCOPE"
      run_promote_legacy_apply "$promote_target"
      notes="Promote apply completed using target=${promote_target}."
      write_domain_state "promote" "apply" "completed" "$notes"
      write_domain_evidence_simple "promote" "apply" "pass" "$notes"
      ;;
    post-check)
      create_domain_backup_snapshot "promote" "post-check"
      resolve_policy_contract
      enforce_security_policy_contract
      enforce_promotion_gate_policy_if_required
      run_deploy post-check "$promote_target"
      notes="Promote post-check completed using target=${promote_target}."
      write_domain_state "promote" "post-check" "completed" "$notes"
      write_domain_evidence_simple "promote" "post-check" "pass" "$notes"
      ;;
    rollback)
      create_domain_backup_snapshot "promote" "rollback"
      backup_dir="$(find_domain_backup_for_restore "promote" "true")"
      restore_remote_domain_backup_snapshot "promote" "$backup_dir"
      run_domain_metadata_restore_from_backup "promote" "$backup_dir"
      notes="Promote rollback restored remote/local metadata from backup=${backup_dir}."
      write_domain_state "promote" "rollback" "completed" "$notes"
      write_domain_evidence_simple "promote" "rollback" "pass" "$notes"
      ;;
  esac
}

trap 'finalize_glpictl_operation "$?"' EXIT
trap 'handle_signal INT' INT
trap 'handle_signal TERM' TERM
trap 'handle_signal HUP' HUP
trap 'handle_signal QUIT' QUIT
ensure_runtime_foundation "$ENVIRONMENT"
begin_operation_log "$ENVIRONMENT" "$OPERATION_ID" "$0 $*"
OPERATION_LOG_INITIALIZED="true"
print_operation_follow_hints
resolve_security_mode
resolve_execution_contract
resolve_execution_overrides
bootstrap_require_privileged="true"
if [[ "$DOMAIN" == "deploy" && "$ACTION" == "check" ]]; then
  bootstrap_require_privileged="false"
fi
ensure_bootstrap_baseline "$SCRIPT_ROOT" "$bootstrap_require_privileged"
run_preflight_checks "$ENVIRONMENT" "$DOMAIN" "$ACTION" "$TARGET" bash git python3 ansible ansible-playbook ansible-inventory

if is_mutating_operation && [[ "$SECURITY_MODE_EFFECTIVE" == "permissive" ]]; then
  ensure_permissive_justification
  persist_permissive_evidence
fi

case "$DOMAIN" in
  deploy) run_deploy "$ACTION" "$TARGET" ;;
  certify) run_certify ;;
  promote) run_promote ;;
  tls) run_tls ;;
  ops) run_ops ;;
  email) run_email ;;
  audit) run_audit ;;
  *)
    echo "Unsupported domain: $DOMAIN (expected deploy|certify|promote|tls|ops|audit|email)" >&2
    exit 1
    ;;
esac

if is_mutating_operation && [[ "$SECURITY_MODE_EFFECTIVE" == "permissive" ]]; then
  persist_permissive_evidence
fi
