#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${2:-staging}"
DOMAIN="${1:-}"
ACTION="${3:-}"
SCOPE="${4:-}"

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: ./scripts/ops-maintenance.sh <users|cert|audit|resume> [environment] [action] [scope]" >&2
  exit 1
fi

RUNTIME_DIR="$SCRIPT_ROOT/../.runtime/$ENVIRONMENT"
INVENTORY_RUNTIME_PATH="$RUNTIME_DIR/inventory.runtime.yml"
PUBLIC_RUNTIME_PATH="$RUNTIME_DIR/public.runtime.yml"
OVERRIDE_RUNTIME_PATH="$RUNTIME_DIR/overrides.runtime.yml"
SECRET_PATH="$RUNTIME_DIR/secrets.yml"
PROTECTED_USERS=("root" "www-data" "mysql")

ensure_runtime_foundation "$ENVIRONMENT"
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" bash git python3 ansible-playbook ansible-inventory
require_runtime_file "$(config_file_path "$ENVIRONMENT")" "product configuration file"
materialize_runtime_from_config "$ENVIRONMENT"
ensure_secret_keys "$ENVIRONMENT"
require_runtime_file "$INVENTORY_RUNTIME_PATH" "runtime inventory"
export ANSIBLE_RUNTIME_INVENTORY="$INVENTORY_RUNTIME_PATH"

case "$DOMAIN" in
  cert|audit)
    require_runtime_file "$PUBLIC_RUNTIME_PATH" "public runtime data"
    require_runtime_file "$OVERRIDE_RUNTIME_PATH" "runtime override data"
    ;;
esac

OPERATION_ID="$(new_operation_id "ops-${DOMAIN}")"
if ! acquire_runtime_lock "$ENVIRONMENT"; then
  exit 1
fi
trap 'release_runtime_lock "$ENVIRONMENT"' EXIT

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
