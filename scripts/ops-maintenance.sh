#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${2:-${GLPI_ENVIRONMENT:-staging}}"
DOMAIN="${1:-}"
ACTION="${3:-}"
SCOPE="${4:-}"
export GLPI_ENVIRONMENT="$ENVIRONMENT"

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: ./scripts/ops-maintenance.sh <users|cert|audit|resume|timezone> [environment] [action] [scope]" >&2
  exit 1
fi

RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
INVENTORY_RUNTIME_PATH="$RUNTIME_DIR/inventory.runtime.yml"
PUBLIC_RUNTIME_PATH="$RUNTIME_DIR/public.runtime.yml"
OVERRIDE_RUNTIME_PATH="$RUNTIME_DIR/overrides.runtime.yml"
SECRET_PATH="$RUNTIME_DIR/secrets.yml"
DB_DEPLOYMENT_MODE="$(resolve_database_deployment_mode_for_environment "$ENVIRONMENT")"
if [[ "$DB_DEPLOYMENT_MODE" == "invalid" ]]; then
  echo "Invalid DATABASE_DEPLOYMENT_MODE in config/$ENVIRONMENT.env (expected self_hosted|managed)." >&2
  exit 1
fi
PROTECTED_USERS=("root" "www-data" "mysql")
TIMEZONE_TARGET=""
TIMEZONE_SUPPORT_ENABLED="false"
TIMEZONE_DB_MODE_RAW="disabled"
TIMEZONE_DB_MODE_EFFECTIVE="disabled"
TIMEZONE_DB_LEGACY_GRANT="false"

ensure_runtime_foundation "$ENVIRONMENT"
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" "ops" "${DOMAIN:-unknown}" "${ACTION:-${SCOPE:-all}}" bash git python3 ansible ansible-playbook ansible-inventory
require_runtime_file "$(config_file_path "$ENVIRONMENT")" "product configuration file"
materialize_runtime_from_config "$ENVIRONMENT"
ensure_secret_keys "$ENVIRONMENT"
require_runtime_file "$INVENTORY_RUNTIME_PATH" "runtime inventory"
export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"

case "$DOMAIN" in
  cert|audit|timezone)
    require_runtime_file "$PUBLIC_RUNTIME_PATH" "public runtime data"
    require_runtime_file "$OVERRIDE_RUNTIME_PATH" "runtime override data"
    ;;
esac

OPERATION_ID="$(new_operation_id "ops-${DOMAIN}")"
if ! acquire_runtime_lock "$ENVIRONMENT"; then
  exit 1
fi
trap 'release_runtime_lock "$ENVIRONMENT" || true; finish_operation_log_stream' EXIT

begin_operation_log "$ENVIRONMENT" "$OPERATION_ID" "$*"
write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "start" "started" "operation started"

run_inline_playbook() {
  local extra_vars_file="${1:-}"
  shift || true
  local playbook_file="$RUNTIME_DIR/.ops-inline-${OPERATION_ID}.yml"
  local rc=0
  cat >"$playbook_file"
  chmod 600 "$playbook_file"
  if [[ -n "$extra_vars_file" ]]; then
    ansible-playbook -i "$INVENTORY_RUNTIME_PATH" "$playbook_file" --extra-vars "@$extra_vars_file"
    rc=$?
  else
    ansible-playbook -i "$INVENTORY_RUNTIME_PATH" "$playbook_file"
    rc=$?
  fi
  rm -f "$playbook_file"
  return "$rc"
}

read_db_root_password() {
  require_runtime_file "$SECRET_PATH" "runtime secret file"
  awk -F"'" '/^glpi_db_root_password:/ {print $2}' "$SECRET_PATH"
}

users_add_os() {
  local username ticket reason
  username="$(read_required_value "OS username to add" "A new operator account requires explicit username." "$RUNTIME_DIR/ops.runtime.yml")"
  ticket="$(read_required_value "Change ticket" "Audit trail is required for user lifecycle." "$RUNTIME_DIR/ops.runtime.yml")"
  reason="$(read_required_value "Change reason" "Audit trail is required for user lifecycle." "$RUNTIME_DIR/ops.runtime.yml")"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-add-os" "started" "creating user $username"
  run_inline_playbook <<EOF
---
- hosts: all
  become: true
  tasks:
    - name: Ensure OS user exists
      ansible.builtin.user:
        name: "${username}"
        shell: /bin/bash
        state: present
        groups: "${GLPI_OPS_GROUP}"
        append: true
EOF
  echo "OS user '$username' ensured. ticket='$ticket' reason='$reason'"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-add-os" "completed" "user ensured"
}

users_disable_os() {
  local username
  username="$(read_required_value "OS username to disable" "Disable first, remove later policy." "$RUNTIME_DIR/ops.runtime.yml")"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-disable-os" "started" "disabling user $username"
  run_inline_playbook <<EOF
---
- hosts: all
  become: true
  tasks:
    - name: Lock OS user account
      ansible.builtin.user:
        name: "${username}"
        password_lock: true
        shell: /usr/sbin/nologin
        state: present
EOF
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-disable-os" "completed" "user disabled"
}

users_remove_os() {
  local username ticket reason
  username="$(read_required_value "OS username to remove" "User removal is destructive and requires confirmation." "$RUNTIME_DIR/ops.runtime.yml")"
  ticket="$(read_required_value "Change ticket" "Audit trail is mandatory for destructive changes." "$RUNTIME_DIR/ops.runtime.yml")"
  reason="$(read_required_value "Change reason" "Audit trail is mandatory for destructive changes." "$RUNTIME_DIR/ops.runtime.yml")"
  for protected in "${PROTECTED_USERS[@]}"; do
    if [[ "$username" == "$protected" ]]; then
      echo "User '$username' is protected and cannot be removed." >&2
      return 1
    fi
  done
  if ! confirm_destructive_action "remove-os-user:${username}" "$ticket" "$reason"; then
    echo "Destructive action cancelled."
    return 1
  fi
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-remove-os" "started" "removing user $username"
  run_inline_playbook <<EOF
---
- hosts: all
  become: true
  tasks:
    - name: Remove OS user account
      ansible.builtin.user:
        name: "${username}"
        state: absent
        remove: true
EOF
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-remove-os" "completed" "user removed"
}

users_add_db() {
  local username password host_pattern db_name root_password
  username="$(read_required_value "DB username to add" "Application/integration DB users must be explicit." "$RUNTIME_DIR/ops.runtime.yml")"
  password="$(read_required_value "DB password" "A password is required to create the DB user." "$RUNTIME_DIR/ops.runtime.yml" true)"
  host_pattern="$(read_required_value "DB host pattern for grants (example: 10.0.0.10 or %)" "Grant scope must be explicit." "$RUNTIME_DIR/ops.runtime.yml")"
  db_name="$(read_required_value "Target database name for grants" "Grant scope must target a specific schema." "$RUNTIME_DIR/ops.runtime.yml")"
  root_password="$(read_db_root_password)"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-add-db" "started" "creating db user $username"
  cat >"$RUNTIME_DIR/.ops-db-user-${OPERATION_ID}.yml" <<EOF
---
ops_db_root_password: '${root_password}'
ops_db_user: '${username}'
ops_db_password: '${password}'
ops_db_host: '${host_pattern}'
ops_db_name: '${db_name}'
EOF
  chmod 600 "$RUNTIME_DIR/.ops-db-user-${OPERATION_ID}.yml"
  run_inline_playbook "$RUNTIME_DIR/.ops-db-user-${OPERATION_ID}.yml" <<'EOF'
---
- hosts: glpi_db
  become: true
  tasks:
    - name: Ensure DB user exists with scoped grants
      community.mysql.mysql_user:
        name: "{{ ops_db_user }}"
        password: "{{ ops_db_password }}"
        host: "{{ ops_db_host }}"
        priv: "{{ ops_db_name }}.*:ALL"
        state: present
        login_user: root
        login_password: "{{ ops_db_root_password }}"
EOF
  rm -f "$RUNTIME_DIR/.ops-db-user-${OPERATION_ID}.yml"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-add-db" "completed" "db user ensured"
}

users_disable_db() {
  local username host_pattern root_password
  username="$(read_required_value "DB username to disable" "Disable first, remove later policy." "$RUNTIME_DIR/ops.runtime.yml")"
  host_pattern="$(read_required_value "DB host pattern (matching existing user host)" "User host is required for safe revocation." "$RUNTIME_DIR/ops.runtime.yml")"
  root_password="$(read_db_root_password)"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-disable-db" "started" "revoking grants for db user $username"
  cat >"$RUNTIME_DIR/.ops-db-disable-${OPERATION_ID}.yml" <<EOF
---
ops_db_root_password: '${root_password}'
ops_db_user: '${username}'
ops_db_host: '${host_pattern}'
EOF
  chmod 600 "$RUNTIME_DIR/.ops-db-disable-${OPERATION_ID}.yml"
  run_inline_playbook "$RUNTIME_DIR/.ops-db-disable-${OPERATION_ID}.yml" <<'EOF'
---
- hosts: glpi_db
  become: true
  tasks:
    - name: Revoke DB user privileges
      community.mysql.mysql_query:
        login_user: root
        login_password: "{{ ops_db_root_password }}"
        query:
          - "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '{{ ops_db_user }}'@'{{ ops_db_host }}';"
          - "FLUSH PRIVILEGES;"
EOF
  rm -f "$RUNTIME_DIR/.ops-db-disable-${OPERATION_ID}.yml"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-disable-db" "completed" "db user disabled"
}

users_remove_db() {
  local username host_pattern ticket reason root_password
  username="$(read_required_value "DB username to remove" "Removal is destructive and must be explicit." "$RUNTIME_DIR/ops.runtime.yml")"
  host_pattern="$(read_required_value "DB host pattern (matching existing user host)" "Drop user requires precise host." "$RUNTIME_DIR/ops.runtime.yml")"
  ticket="$(read_required_value "Change ticket" "Audit trail is mandatory for destructive changes." "$RUNTIME_DIR/ops.runtime.yml")"
  reason="$(read_required_value "Change reason" "Audit trail is mandatory for destructive changes." "$RUNTIME_DIR/ops.runtime.yml")"
  if ! confirm_destructive_action "remove-db-user:${username}@${host_pattern}" "$ticket" "$reason"; then
    echo "Destructive action cancelled."
    return 1
  fi
  root_password="$(read_db_root_password)"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-remove-db" "started" "removing db user $username"
  cat >"$RUNTIME_DIR/.ops-db-remove-${OPERATION_ID}.yml" <<EOF
---
ops_db_root_password: '${root_password}'
ops_db_user: '${username}'
ops_db_host: '${host_pattern}'
EOF
  chmod 600 "$RUNTIME_DIR/.ops-db-remove-${OPERATION_ID}.yml"
  run_inline_playbook "$RUNTIME_DIR/.ops-db-remove-${OPERATION_ID}.yml" <<'EOF'
---
- hosts: glpi_db
  become: true
  tasks:
    - name: Remove DB user
      community.mysql.mysql_user:
        name: "{{ ops_db_user }}"
        host: "{{ ops_db_host }}"
        state: absent
        login_user: root
        login_password: "{{ ops_db_root_password }}"
EOF
  rm -f "$RUNTIME_DIR/.ops-db-remove-${OPERATION_ID}.yml"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "users-remove-db" "completed" "db user removed"
}

users_glpi_manual() {
  local action_name="$1"
  local glpi_user ticket reason
  glpi_user="$(read_required_value "GLPI username (${action_name})" "GLPI user lifecycle requires explicit identity." "$RUNTIME_DIR/ops.runtime.yml")"
  ticket="$(read_required_value "Change ticket" "Audit trail is mandatory for GLPI user lifecycle." "$RUNTIME_DIR/ops.runtime.yml")"
  reason="$(read_required_value "Change reason" "Audit trail is mandatory for GLPI user lifecycle." "$RUNTIME_DIR/ops.runtime.yml")"
  echo "GLPI user automation is manual-controlled in this version."
  echo "Checklist:"
  echo "1. Login in GLPI admin panel."
  echo "2. Perform action '${action_name}' for user '${glpi_user}'."
  echo "3. Capture evidence (screenshot or audit trail)."
  if ! prompt_yes_no "Confirm the manual GLPI step was completed?"; then
    echo "GLPI manual workflow not confirmed; operation will fail." >&2
    return 1
  fi
  echo "GLPI manual workflow confirmed for user '${glpi_user}', ticket '${ticket}', reason '${reason}'."
}

cert_check() {
  local cert_path days
  cert_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_certificate_path" || true)"
  [[ -z "${cert_path// }" ]] && cert_path="$(awk -F'"' '/glpi_tls_certificate_path:/ {print $2}' "$PUBLIC_RUNTIME_PATH" | head -n1)"
  if [[ -z "$cert_path" ]]; then
    cert_path="/etc/ssl/certs/glpi-staging.crt"
  fi
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "cert-check" "started" "checking certificate expiry"
  days="$(ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "end=\$(openssl x509 -enddate -noout -in '$cert_path' | cut -d= -f2); end_ts=\$(date -d \"\$end\" +%s); now_ts=\$(date +%s); echo \$(( (end_ts-now_ts)/86400 ))" -o | awk -F'>>' 'NR==1 {gsub(/ /,"",$2); print $2}')"
  if [[ -z "$days" ]]; then
    echo "Unable to compute certificate days to expiry." >&2
    return 1
  fi
  echo "Certificate path: $cert_path"
  echo "Days to expiry: $days"
  if ((days <= CERT_RENEWAL_WARN_DAYS)); then
    echo "WARNING: certificate expires in <= ${CERT_RENEWAL_WARN_DAYS} days."
  fi
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "cert-check" "completed" "days-to-expiry=$days"
}

cert_apply() {
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "cert-apply" "started" "applying provided certificate"
  bash "$SCRIPT_ROOT/manage-tls.sh" install-provided "$ENVIRONMENT"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "cert-apply" "completed" "certificate applied"
}

cert_renew() {
  cert_check
  cert_apply
}

audit_check() {
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "audit-check" "started" "running operational audit checks"
  ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
  invoke_ansible "$ENVIRONMENT" "app,db" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "audit-check" "completed" "audit checks completed"
}

normalize_bool_local() {
  local value="${1:-}"
  local default_value="${2:-false}"
  case "${value,,}" in
    true|1|yes|on) echo "true" ;;
    false|0|no|off|"") echo "false" ;;
    *) echo "$default_value" ;;
  esac
}

shell_escape_single_quotes() {
  local value="$1"
  value="${value//\'/\'\"\'\"\'}"
  printf "%s" "$value"
}

read_runtime_effective_value() {
  local key="$1"
  local default_value="${2:-}"
  local value
  value="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "$key" || true)"
  [[ -z "${value// }" ]] && value="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "$key" || true)"
  [[ -z "${value// }" ]] && value="$default_value"
  echo "$value"
}

read_db_app_password() {
  require_runtime_file "$SECRET_PATH" "runtime secret file"
  read_yaml_top_level_value "$SECRET_PATH" "glpi_db_password" || true
}

read_db_managed_admin_password() {
  require_runtime_file "$SECRET_PATH" "runtime secret file"
  read_yaml_top_level_value "$SECRET_PATH" "glpi_db_managed_admin_password" || true
}

timezone_load_runtime_contract() {
  TIMEZONE_TARGET="$(read_runtime_effective_value "timezone_name" "UTC")"
  TIMEZONE_SUPPORT_ENABLED="$(normalize_bool_local "$(read_runtime_effective_value "glpi_timezone_support_enabled" "false")" "false")"
  TIMEZONE_DB_MODE_RAW="$(read_runtime_effective_value "glpi_timezone_db_mode" "disabled")"
  TIMEZONE_DB_MODE_RAW="${TIMEZONE_DB_MODE_RAW,,}"
  TIMEZONE_DB_LEGACY_GRANT="$(normalize_bool_local "$(read_runtime_effective_value "glpi_timezone_db_legacy_grant" "false")" "false")"
  case "$TIMEZONE_DB_MODE_RAW" in
    disabled|validate|apply) ;;
    *)
      echo "Invalid GLPI timezone DB mode: ${TIMEZONE_DB_MODE_RAW} (expected disabled|validate|apply)." >&2
      return 1
      ;;
  esac
  TIMEZONE_DB_MODE_EFFECTIVE="$TIMEZONE_DB_MODE_RAW"
  if [[ "$DB_DEPLOYMENT_MODE" == "managed" && "$TIMEZONE_SUPPORT_ENABLED" == "true" && "$TIMEZONE_DB_MODE_EFFECTIVE" == "disabled" ]]; then
    TIMEZONE_DB_MODE_EFFECTIVE="validate"
  fi
  return 0
}

timezone_check_os() {
  local timezone_escaped
  timezone_escaped="$(shell_escape_single_quotes "$TIMEZONE_TARGET")"
  if ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "current_tz=\$(timedatectl show -p Timezone --value 2>/dev/null || true); [[ \"\$current_tz\" == '${timezone_escaped}' ]]" -o >/dev/null 2>&1; then
    echo "OS timezone check: PASS (${TIMEZONE_TARGET})"
    return 0
  fi
  echo "OS timezone check: FAIL (expected ${TIMEZONE_TARGET})"
  return 1
}

timezone_check_php() {
  local timezone_escaped php_service
  timezone_escaped="$(shell_escape_single_quotes "$TIMEZONE_TARGET")"
  php_service="$(read_runtime_effective_value "glpi_php_fpm_service" "php8.3-fpm")"
  if ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "php_tz=\$(php -r 'echo date_default_timezone_get();' 2>/dev/null || true); systemctl is-active --quiet '${php_service}'; [[ \"\$php_tz\" == '${timezone_escaped}' ]]" -o >/dev/null 2>&1; then
    echo "PHP timezone check: PASS (${TIMEZONE_TARGET})"
    return 0
  fi
  echo "PHP timezone check: FAIL (expected ${TIMEZONE_TARGET})"
  return 1
}

timezone_check_db_self_hosted() {
  local root_password timezone_escaped
  root_password="$(read_db_root_password)"
  if [[ -z "${root_password// }" ]]; then
    echo "DB timezone check (self_hosted): FAIL (missing DATABASE_ROOT_PASSWORD materialized runtime secret)"
    return 1
  fi
  timezone_escaped="$(shell_escape_single_quotes "$TIMEZONE_TARGET")"
  if ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='$(shell_escape_single_quotes "$root_password")' mysql --protocol=SOCKET --socket=/run/mysqld/mysqld.sock --user=root --batch --skip-column-names --silent --execute=\"SELECT CASE WHEN CONVERT_TZ('2000-01-01 00:00:00','UTC','${timezone_escaped}') IS NULL THEN 0 ELSE 1 END;\" | grep -qx '1'" -o >/dev/null 2>&1; then
    echo "DB timezone check (self_hosted): PASS (${TIMEZONE_TARGET})"
    return 0
  fi
  echo "DB timezone check (self_hosted): FAIL (timezone tables may be missing)"
  return 1
}

timezone_check_db_managed_attempt() {
  local db_user="$1"
  local db_password="$2"
  local db_host db_port db_name
  local timezone_escaped db_host_escaped db_port_escaped db_user_escaped db_password_escaped db_name_escaped

  db_host="$(read_runtime_effective_value "glpi_db_host" "")"
  db_port="$(read_runtime_effective_value "mariadb_port" "3306")"
  db_name="$(read_runtime_effective_value "glpi_db_name" "")"
  [[ -z "${db_host// }" || -z "${db_name// }" ]] && return 1

  timezone_escaped="$(shell_escape_single_quotes "$TIMEZONE_TARGET")"
  db_host_escaped="$(shell_escape_single_quotes "$db_host")"
  db_port_escaped="$(shell_escape_single_quotes "$db_port")"
  db_user_escaped="$(shell_escape_single_quotes "$db_user")"
  db_password_escaped="$(shell_escape_single_quotes "$db_password")"
  db_name_escaped="$(shell_escape_single_quotes "$db_name")"

  ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='${db_password_escaped}' mysql --protocol=TCP --host='${db_host_escaped}' --port='${db_port_escaped}' --user='${db_user_escaped}' --database='${db_name_escaped}' --batch --skip-column-names --silent --execute=\"SELECT CASE WHEN CONVERT_TZ('2000-01-01 00:00:00','UTC','${timezone_escaped}') IS NULL THEN 0 ELSE 1 END;\" | grep -qx '1'" -o >/dev/null 2>&1
}

timezone_check_db_managed() {
  local app_user app_password admin_password
  app_user="$(read_runtime_effective_value "glpi_db_user" "")"
  app_password="$(read_db_app_password)"
  admin_password="$(read_db_managed_admin_password)"

  if [[ -n "${app_user// }" && -n "${app_password// }" ]] && timezone_check_db_managed_attempt "$app_user" "$app_password"; then
    echo "DB timezone check (managed): PASS (user=${app_user})"
    return 0
  fi
  if [[ -n "${admin_password// }" ]] && timezone_check_db_managed_attempt "root" "$admin_password"; then
    echo "DB timezone check (managed): PASS (user=root)"
    return 0
  fi
  if [[ -n "${admin_password// }" ]] && timezone_check_db_managed_attempt "admin" "$admin_password"; then
    echo "DB timezone check (managed): PASS (user=admin)"
    return 0
  fi
  echo "DB timezone check (managed): FAIL (timezone tables may be missing or credentials/reachability failed)"
  return 1
}

timezone_apply_os() {
  local timezone_escaped
  timezone_escaped="$(shell_escape_single_quotes "$TIMEZONE_TARGET")"
  ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "timedatectl set-timezone '${timezone_escaped}'" -o >/dev/null
  echo "OS timezone apply: PASS (${TIMEZONE_TARGET})"
}

timezone_apply_php() {
  local timezone_escaped php_service php_version_major_minor
  php_service="$(read_runtime_effective_value "glpi_php_fpm_service" "php8.3-fpm")"
  php_version_major_minor="$(read_runtime_effective_value "glpi_php_fpm_socket" "/run/php/php8.3-fpm.sock" | sed -n "s|.*php\\([0-9]\\+\\.[0-9]\\+\\)-fpm.*|\\1|p")"
  [[ -z "${php_version_major_minor// }" ]] && php_version_major_minor="8.3"
  timezone_escaped="$(shell_escape_single_quotes "$TIMEZONE_TARGET")"
  ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "set -e; for sapi in fpm cli; do install -d -m 0755 /etc/php/${php_version_major_minor}/\${sapi}/conf.d; printf '%s\n' 'date.timezone = ${timezone_escaped}' > /etc/php/${php_version_major_minor}/\${sapi}/conf.d/99-glpi-timezone.ini; done; systemctl restart '${php_service}'" -o >/dev/null
  echo "PHP timezone apply: PASS (${TIMEZONE_TARGET})"
}

timezone_apply_db_self_hosted() {
  local root_password db_user db_grant_host user_sql host_sql
  root_password="$(read_db_root_password)"
  db_user="$(read_runtime_effective_value "glpi_db_user" "")"
  db_grant_host="$(read_runtime_effective_value "db_grant_host" "%")"
  if [[ -z "${root_password// }" ]]; then
    echo "DB timezone apply (self_hosted): FAIL (missing DATABASE_ROOT_PASSWORD materialized runtime secret)"
    return 1
  fi
  ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "set -euo pipefail; tz_loader=\$(command -v mariadb-tzinfo-to-sql || command -v mysql_tzinfo_to_sql || true); if [[ -z \"\$tz_loader\" ]]; then exit 2; fi; MYSQL_PWD='$(shell_escape_single_quotes "$root_password")' \"\$tz_loader\" /usr/share/zoneinfo | MYSQL_PWD='$(shell_escape_single_quotes "$root_password")' mysql --protocol=SOCKET --socket=/run/mysqld/mysqld.sock --user=root mysql; systemctl restart mariadb" -o >/dev/null
  echo "DB timezone apply (self_hosted): PASS (timezone tables loaded)"
  if [[ "$TIMEZONE_DB_LEGACY_GRANT" == "true" && -n "${db_user// }" ]]; then
    user_sql="${db_user//\'/\'\'}"
    host_sql="${db_grant_host//\'/\'\'}"
    ansible glpi_db -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "MYSQL_PWD='$(shell_escape_single_quotes "$root_password")' mysql --protocol=SOCKET --socket=/run/mysqld/mysqld.sock --user=root --execute=\"GRANT SELECT ON mysql.time_zone_name TO '${user_sql}'@'${host_sql}'; FLUSH PRIVILEGES;\"" -o >/dev/null
    echo "DB timezone apply (self_hosted): PASS (legacy grant applied to ${db_user}@${db_grant_host})"
  fi
  return 0
}

timezone_apply_db_managed_if_confirmed() {
  local admin_password db_host db_port
  admin_password="$(read_db_managed_admin_password)"
  db_host="$(read_runtime_effective_value "glpi_db_host" "")"
  db_port="$(read_runtime_effective_value "mariadb_port" "3306")"

  if [[ "$TIMEZONE_DB_MODE_EFFECTIVE" != "apply" ]]; then
    echo "DB timezone apply (managed): SKIP (effective mode=${TIMEZONE_DB_MODE_EFFECTIVE}, validation-only)."
    return 0
  fi
  if [[ -z "${admin_password// }" ]]; then
    echo "DB timezone apply (managed): WARN (DATABASE_MANAGED_ADMIN_PASSWORD is missing)."
    return 0
  fi
  if ! prompt_yes_no "Managed DB timezone apply may affect other databases in the same instance. Proceed with DB timezone-table load now?"; then
    echo "DB timezone apply (managed): SKIP (operator chose not to execute)."
    return 0
  fi

  if ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "set -euo pipefail; tz_loader=\$(command -v mariadb-tzinfo-to-sql || command -v mysql_tzinfo_to_sql || true); if [[ -z \"\$tz_loader\" ]]; then exit 2; fi; \"\$tz_loader\" /usr/share/zoneinfo | MYSQL_PWD='$(shell_escape_single_quotes "$admin_password")' mysql --protocol=TCP --host='$(shell_escape_single_quotes "$db_host")' --port='$(shell_escape_single_quotes "$db_port")' --user=root mysql" -o >/dev/null 2>&1; then
    echo "DB timezone apply (managed): PASS (executed with user=root)"
    return 0
  fi
  if ansible glpi_app -i "$INVENTORY_RUNTIME_PATH" -b -m shell -a "set -euo pipefail; tz_loader=\$(command -v mariadb-tzinfo-to-sql || command -v mysql_tzinfo_to_sql || true); if [[ -z \"\$tz_loader\" ]]; then exit 2; fi; \"\$tz_loader\" /usr/share/zoneinfo | MYSQL_PWD='$(shell_escape_single_quotes "$admin_password")' mysql --protocol=TCP --host='$(shell_escape_single_quotes "$db_host")' --port='$(shell_escape_single_quotes "$db_port")' --user=admin mysql" -o >/dev/null 2>&1; then
    echo "DB timezone apply (managed): PASS (executed with user=admin)"
    return 0
  fi
  echo "DB timezone apply (managed): WARN (failed with users root/admin)."
  return 0
}

timezone_check() {
  local has_failure="false"
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "timezone-check" "started" "checking timezone readiness"
  timezone_load_runtime_contract || return 1
  echo "Timezone support: enabled=${TIMEZONE_SUPPORT_ENABLED} db_mode=${TIMEZONE_DB_MODE_RAW} effective_db_mode=${TIMEZONE_DB_MODE_EFFECTIVE} deployment_mode=${DB_DEPLOYMENT_MODE} target_timezone=${TIMEZONE_TARGET}"

  if ! timezone_check_os; then
    has_failure="true"
  fi
  if ! timezone_check_php; then
    has_failure="true"
  fi

  if [[ "$TIMEZONE_SUPPORT_ENABLED" == "true" && "$TIMEZONE_DB_MODE_EFFECTIVE" != "disabled" ]]; then
    if [[ "$DB_DEPLOYMENT_MODE" == "managed" ]]; then
      if ! timezone_check_db_managed; then
        has_failure="true"
      fi
    else
      if ! timezone_check_db_self_hosted; then
        has_failure="true"
      fi
    fi
  else
    echo "DB timezone check: SKIP (timezone support disabled or DB mode disabled)."
  fi

  if [[ "$has_failure" == "true" ]]; then
    write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "timezone-check" "failed" "timezone readiness check failed"
    return 1
  fi
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "timezone-check" "completed" "timezone readiness check passed"
  return 0
}

timezone_apply() {
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "timezone-apply" "started" "applying timezone settings"
  timezone_load_runtime_contract || return 1
  echo "Timezone support: enabled=${TIMEZONE_SUPPORT_ENABLED} db_mode=${TIMEZONE_DB_MODE_RAW} effective_db_mode=${TIMEZONE_DB_MODE_EFFECTIVE} deployment_mode=${DB_DEPLOYMENT_MODE} target_timezone=${TIMEZONE_TARGET}"

  timezone_apply_os || return 1
  timezone_apply_php || return 1

  if [[ "$TIMEZONE_SUPPORT_ENABLED" == "true" && "$TIMEZONE_DB_MODE_EFFECTIVE" != "disabled" ]]; then
    if [[ "$DB_DEPLOYMENT_MODE" == "managed" ]]; then
      timezone_apply_db_managed_if_confirmed || return 1
    else
      if [[ "$TIMEZONE_DB_MODE_EFFECTIVE" == "apply" ]]; then
        timezone_apply_db_self_hosted || return 1
      else
        echo "DB timezone apply (self_hosted): SKIP (effective mode=${TIMEZONE_DB_MODE_EFFECTIVE})."
      fi
    fi
  else
    echo "DB timezone apply: SKIP (timezone support disabled or DB mode disabled)."
  fi

  timezone_check
}

resume_last_operation() {
  local latest_state
  latest_state="$(latest_operation_state "$ENVIRONMENT")"
  if [[ -z "$latest_state" ]]; then
    echo "No previous operation state found to resume." >&2
    return 1
  fi
  local latest_status latest_stage latest_operation
  latest_status="$(read_state_field "$latest_state" "status")"
  latest_stage="$(read_state_field "$latest_state" "stage")"
  latest_operation="$(read_state_field "$latest_state" "operation_id")"
  echo "Latest state: $latest_state"
  echo "Operation: $latest_operation"
  echo "Status: $latest_status"
  echo "Stage: $latest_stage"
  if [[ "$latest_status" == "completed" ]]; then
    echo "Latest operation is already completed. Nothing to resume."
    return 0
  fi
  if [[ "$latest_stage" == cert-* ]]; then
    cert_apply
    return 0
  fi
  if [[ "$latest_stage" == users-* ]]; then
    echo "Resume hint: rerun users operation manually with same action and scope."
    return 0
  fi
  if [[ "$latest_stage" == "audit-check" ]]; then
    audit_check
    return 0
  fi
  echo "No automatic resume path for stage '$latest_stage'."
  return 1
}

users_dispatch() {
  local users_action="$1"
  local users_scope="$2"
  case "$users_scope" in
    os)
      case "$users_action" in
        add) users_add_os ;;
        disable) users_disable_os ;;
        remove) users_remove_os ;;
        *) echo "Unsupported users action: $users_action" >&2; return 1 ;;
      esac
      ;;
    db)
      if [[ "$DB_DEPLOYMENT_MODE" == "managed" ]]; then
        echo "DB user lifecycle subcommands are not supported when DATABASE_DEPLOYMENT_MODE=managed." >&2
        echo "RDS/managed DB operations must be executed through the database administration workflow." >&2
        return 1
      fi
      case "$users_action" in
        add) users_add_db ;;
        disable) users_disable_db ;;
        remove) users_remove_db ;;
        *) echo "Unsupported users action: $users_action" >&2; return 1 ;;
      esac
      ;;
    glpi)
      users_glpi_manual "$users_action"
      ;;
    *)
      echo "Unsupported users scope: $users_scope (expected: os|db|glpi)" >&2
      return 1
      ;;
  esac
}

set +e
case "$DOMAIN" in
  users)
    users_dispatch "${ACTION:-add}" "${SCOPE:-os}"
    RESULT=$?
    ;;
  cert)
    case "${ACTION:-check}" in
      check) cert_check; RESULT=$? ;;
      apply) cert_apply; RESULT=$? ;;
      renew) cert_renew; RESULT=$? ;;
      *) echo "Unsupported cert action: $ACTION" >&2; RESULT=1 ;;
    esac
    ;;
  audit)
    if [[ "${ACTION:-check}" != "check" ]]; then
      echo "Supported audit action: check" >&2
      RESULT=1
    else
      audit_check
      RESULT=$?
    fi
    ;;
  resume)
    resume_last_operation
    RESULT=$?
    ;;
  timezone)
    case "${ACTION:-check}" in
      check) timezone_check; RESULT=$? ;;
      apply) timezone_apply; RESULT=$? ;;
      *) echo "Unsupported timezone action: $ACTION (expected check|apply)" >&2; RESULT=1 ;;
    esac
    ;;
  *)
    echo "Unsupported domain: $DOMAIN" >&2
    RESULT=1
    ;;
esac
set -e

if [[ "$RESULT" -eq 0 ]]; then
  write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "finish" "completed" "operation completed"
  complete_operation_log "$ENVIRONMENT" "$OPERATION_ID" "completed"
  echo "Operation completed successfully."
  exit 0
fi

write_operation_state "$ENVIRONMENT" "$OPERATION_ID" "finish" "failed" "operation failed"
complete_operation_log "$ENVIRONMENT" "$OPERATION_ID" "failed" "$DOMAIN/$ACTION/$SCOPE" "Review operation log and state file."
echo "Operation failed." >&2
exit 1
