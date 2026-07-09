#!/usr/bin/env bash
set -euo pipefail

COMMON_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFLIGHT_FORCE_CONTINUE="${PREFLIGHT_FORCE_CONTINUE:-false}"
PREFLIGHT_AUTO_INSTALL="${PREFLIGHT_AUTO_INSTALL:-prompt}"
GLPI_OPS_GROUP="${GLPI_OPS_GROUP:-glpiops}"
CERT_RENEWAL_WARN_DAYS="${CERT_RENEWAL_WARN_DAYS:-30}"
GLPI_EXECUTION_MODE="${GLPI_EXECUTION_MODE:-}"
GLPI_HOST_ROLE="${GLPI_HOST_ROLE:-}"
OPERATION_LOGGER_PID="${OPERATION_LOGGER_PID:-}"
OPERATION_LOGGER_FIFO="${OPERATION_LOGGER_FIFO:-}"
OPERATION_LOG_STDOUT_FD="${OPERATION_LOG_STDOUT_FD:-}"
OPERATION_LOG_STDERR_FD="${OPERATION_LOG_STDERR_FD:-}"

write_step() {
  printf '\n==> %s\n' "$1"
}

assert_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Command '$name' is required but was not found in PATH." >&2
    exit 1
  fi
}

ensure_directory() {
  local path="$1"
  mkdir -p "$path"
}

expand_home_path() {
  local path="$1"
  if [[ "$path" == "~/"* ]]; then
    printf '%s\n' "${HOME}${path#\~}"
    return 0
  fi
  printf '%s\n' "$path"
}

current_uid() {
  id -u
}

is_root_user() {
  [[ "$(current_uid)" -eq 0 ]]
}

current_operator_user() {
  if is_root_user && [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    echo "$SUDO_USER"
    return
  fi
  id -un
}

file_mode_octal() {
  local path="$1"
  stat -c '%a' "$path" 2>/dev/null || true
}

prompt_yes_no() {
  local prompt="$1"
  local answer=""
  while true; do
    echo "$prompt [y/n]"
    if ! read -r answer; then
      echo "No interactive input available; treating response as 'no'." >&2
      return 1
    fi
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "Please answer 'y' or 'n'." ;;
    esac
  done
}

offer_fix_then_execute() {
  local title="$1"
  local command_to_run="$2"

  echo "$title"
  echo "Suggested fix command:"
  echo "  $command_to_run"
  if ! prompt_yes_no "Apply automatic fix now?"; then
    return 1
  fi
  if bash -lc "$command_to_run"; then
    return 0
  fi
  echo "Automatic fix failed. Apply manually and rerun." >&2
  return 1
}

ensure_execute_permission() {
  local path="$1"
  local mode
  mode="$(file_mode_octal "$path")"
  if [[ -x "$path" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Missing execute permission on '$path'."
    echo "Suggested fix command:"
    printf '  chmod +x %q\n' "$path"
    echo "No interactive input available; applying safe mandatory script permission fix."
    chmod +x "$path"
    [[ -x "$path" ]]
    return
  fi
  if offer_fix_then_execute "Missing execute permission on '$path'." "chmod +x '$path'"; then
    [[ -x "$path" ]]
    return
  fi
  return 1
}

ensure_script_directory_executable() {
  local dir_path="$1"
  local failures=0
  local script_path=""
  while IFS= read -r -d '' script_path; do
    if ! ensure_execute_permission "$script_path"; then
      failures=$((failures + 1))
    fi
  done < <(find "$dir_path" -maxdepth 1 -type f -name "*.sh" -print0)
  ((failures == 0))
}

ensure_mode() {
  local path="$1"
  local expected="$2"
  local mode fix_cmd
  mode="$(file_mode_octal "$path")"
  if [[ "$mode" == "$expected" ]]; then
    return 0
  fi
  printf -v fix_cmd "chmod u-s,g-s,o-t %q && chmod %s %q" "$path" "$expected" "$path"
  if offer_fix_then_execute "Path '$path' has mode '${mode:-unknown}', expected '$expected'." "$fix_cmd"; then
    mode="$(file_mode_octal "$path")"
    [[ "$mode" == "$expected" ]]
    return
  fi
  return 1
}

ensure_directory_mode() {
  local path="$1"
  local expected="$2"
  ensure_directory "$path"
  ensure_mode "$path" "$expected"
}

ensure_group_exists_and_membership() {
  local group_name="$1"
  local current_user
  current_user="$(current_operator_user)"

  if ! getent group "$group_name" >/dev/null 2>&1; then
    local create_cmd
    if command -v sudo >/dev/null 2>&1 && ! is_root_user; then
      create_cmd="sudo groupadd '$group_name'"
    else
      create_cmd="groupadd '$group_name'"
    fi
    if ! offer_fix_then_execute "Required operator group '$group_name' does not exist." "$create_cmd"; then
      return 1
    fi
  fi

  if id -nG "$current_user" | tr ' ' '\n' | grep -Fx "$group_name" >/dev/null 2>&1; then
    return 0
  fi

  local add_cmd
  if command -v sudo >/dev/null 2>&1 && ! is_root_user; then
    add_cmd="sudo usermod -aG '$group_name' '$current_user'"
  else
    add_cmd="usermod -aG '$group_name' '$current_user'"
  fi

  if offer_fix_then_execute "User '$current_user' is not a member of required group '$group_name'." "$add_cmd"; then
    echo "User was added to '$group_name'. Log out and log back in before rerunning." >&2
  fi
  return 1
}

ensure_sudo_ready() {
  if is_root_user; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required for non-root execution." >&2
    return 1
  fi
  if sudo -v; then
    return 0
  fi
  echo "Unable to validate sudo privileges for current user." >&2
  echo "The password requested by sudo is from the local Linux VM/host user." >&2
  echo "It is not a MySQL, RDS, or SSH credential." >&2
  return 1
}

bootstrap_marker_path() {
  echo "$SCRIPT_ROOT/../.runtime/bootstrap.completed"
}

write_bootstrap_marker() {
  local marker
  marker="$(bootstrap_marker_path)"
  ensure_directory "$SCRIPT_ROOT/../.runtime"
  printf "bootstrap_completed_at=%s\nbootstrap_completed_by=%s\n" "$(date -u +%FT%TZ)" "$(current_operator_user)" >"$marker"
  chmod 600 "$marker"
}

require_bootstrap_marker() {
  local marker
  marker="$(bootstrap_marker_path)"
  if [[ -f "$marker" ]]; then
    return 0
  fi
  echo "Missing bootstrap marker: $marker" >&2
  echo "Run 'bash scripts/bootstrap-permissions.sh' first." >&2
  return 1
}

ensure_bootstrap_baseline() {
  local script_root="$1"
  local require_privileged="${2:-true}"
  ensure_script_directory_executable "$script_root"
  if [[ "$require_privileged" == "true" ]]; then
    ensure_sudo_ready
    ensure_group_exists_and_membership "$GLPI_OPS_GROUP"
  fi
  ensure_directory_mode "$script_root/../.runtime" "700"
  if [[ ! -f "$(bootstrap_marker_path)" ]]; then
    write_step "Bootstrap marker not found. Creating baseline automatically."
    write_bootstrap_marker
  fi
  ensure_mode "$(bootstrap_marker_path)" "600"
}

runtime_environment_root() {
  local environment="$1"
  echo "$SCRIPT_ROOT/../.runtime/$environment"
}

runtime_logs_dir() {
  local environment="$1"
  echo "$(runtime_environment_root "$environment")/logs"
}

runtime_state_dir() {
  local environment="$1"
  echo "$(runtime_environment_root "$environment")/state"
}

runtime_evidence_dir() {
  local environment="$1"
  echo "$(runtime_environment_root "$environment")/evidence"
}

ensure_runtime_foundation() {
  local environment="$1"
  ensure_directory_mode "$(runtime_environment_root "$environment")" "700"
  ensure_directory_mode "$(runtime_logs_dir "$environment")" "700"
  ensure_directory_mode "$(runtime_state_dir "$environment")" "700"
  ensure_directory_mode "$(runtime_evidence_dir "$environment")" "700"
}

new_operation_id() {
  local prefix="$1"
  echo "${prefix}-$(date +%Y%m%d-%H%M%S)"
}

operation_log_path() {
  local environment="$1"
  local operation_id="$2"
  echo "$(runtime_logs_dir "$environment")/${operation_id}.log"
}

operation_summary_path() {
  local environment="$1"
  local operation_id="$2"
  echo "$(runtime_logs_dir "$environment")/${operation_id}.summary.yml"
}

operation_state_path() {
  local environment="$1"
  local operation_id="$2"
  echo "$(runtime_state_dir "$environment")/${operation_id}.state.yml"
}

runtime_lock_path() {
  local environment="$1"
  echo "$(runtime_state_dir "$environment")/.ops-maintenance.lock"
}

mask_sensitive() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo ""
    return
  fi
  local len="${#value}"
  if ((len <= 4)); then
    echo "****"
    return
  fi
  local tail="${value: -2}"
  echo "****${tail}"
}

begin_operation_log() {
  local environment="$1"
  local operation_id="$2"
  local command_line="$3"
  local log_path fifo_root fifo_dir fifo_path
  log_path="$(operation_log_path "$environment" "$operation_id")"
  local summary_path
  summary_path="$(operation_summary_path "$environment" "$operation_id")"

  {
    echo "---"
    echo "operation_id: '$operation_id'"
    echo "environment: '$environment'"
    echo "operator: '$(id -un)'"
    echo "host: '$(hostname)'"
    echo "command: '$command_line'"
    echo "started_at: '$(date -u +%FT%TZ)'"
    echo "status: 'started'"
  } >"$summary_path"
  chmod 600 "$summary_path"

  fifo_root="${GLPI_OPERATION_FIFO_ROOT:-/tmp}"
  fifo_dir="$(mktemp -d "${fifo_root%/}/glpi-operation-log.XXXXXX")"
  chmod 700 "$fifo_dir"
  fifo_path="$fifo_dir/stream"
  mkfifo -m 600 "$fifo_path"

  exec {OPERATION_LOG_STDOUT_FD}>&1
  exec {OPERATION_LOG_STDERR_FD}>&2

  (
    while IFS= read -r line; do
      printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$line"
    done <"$fifo_path" | tee -a "$log_path"
  ) &
  OPERATION_LOGGER_PID="$!"
  OPERATION_LOGGER_FIFO="$fifo_path"

  exec >"$fifo_path" 2>&1
  rm -f "$fifo_path"
  rmdir "$fifo_dir" 2>/dev/null || true
  echo "Operation log: $log_path"
}

finish_operation_log_stream() {
  local logger_pid="${OPERATION_LOGGER_PID:-}"
  if [[ -z "$logger_pid" ]]; then
    return 0
  fi

  if [[ -n "${OPERATION_LOG_STDOUT_FD:-}" && -n "${OPERATION_LOG_STDERR_FD:-}" ]]; then
    exec 1>&${OPERATION_LOG_STDOUT_FD} 2>&${OPERATION_LOG_STDERR_FD}
    exec {OPERATION_LOG_STDOUT_FD}>&-
    exec {OPERATION_LOG_STDERR_FD}>&-
  fi
  wait "$logger_pid" || true
  OPERATION_LOGGER_PID=""
  OPERATION_LOGGER_FIFO=""
  OPERATION_LOG_STDOUT_FD=""
  OPERATION_LOG_STDERR_FD=""
}

complete_operation_log() {
  local environment="$1"
  local operation_id="$2"
  local status="$3"
  local failed_stage="${4:-}"
  local remediation_hint="${5:-}"
  local summary_path
  summary_path="$(operation_summary_path "$environment" "$operation_id")"
  local status_line
  status_line="$(printf "status: '%s'" "$status")"
  sed -i "s/^status: .*/$status_line/" "$summary_path"
  {
    echo "completed_at: '$(date -u +%FT%TZ)'"
    echo "failed_stage: '${failed_stage}'"
    echo "remediation_hint: '${remediation_hint}'"
  } >>"$summary_path"
}

acquire_runtime_lock() {
  local environment="$1"
  local lock_path
  lock_path="$(runtime_lock_path "$environment")"
  if [[ -f "$lock_path" ]]; then
    echo "Another maintenance execution appears active. Lock file: $lock_path" >&2
    return 1
  fi
  printf "pid=%s\nuser=%s\nstarted_at=%s\n" "$$" "$(id -un)" "$(date -u +%FT%TZ)" >"$lock_path"
  chmod 600 "$lock_path"
  return 0
}

release_runtime_lock() {
  local environment="$1"
  local lock_path
  lock_path="$(runtime_lock_path "$environment")"
  rm -f "$lock_path"
}

write_operation_state() {
  local environment="$1"
  local operation_id="$2"
  local stage="$3"
  local status="$4"
  local message="${5:-}"
  local state_path
  state_path="$(operation_state_path "$environment" "$operation_id")"
  {
    echo "---"
    echo "operation_id: '$operation_id'"
    echo "environment: '$environment'"
    echo "stage: '$stage'"
    echo "status: '$status'"
    echo "message: '$message'"
    echo "updated_at: '$(date -u +%FT%TZ)'"
  } >"$state_path"
  chmod 600 "$state_path"
}

latest_operation_state() {
  local environment="$1"
  local state_dir
  state_dir="$(runtime_state_dir "$environment")"
  find "$state_dir" -maxdepth 1 -type f -name "*.state.yml" | sort | tail -n1
}

read_state_field() {
  local path="$1"
  local field="$2"
  awk -F"'" -v key="$field" '$1 ~ "^" key ": " {print $2; exit}' "$path"
}

confirm_destructive_action() {
  local action="$1"
  local ticket="$2"
  local reason="$3"
  if [[ -z "${ticket// }" || -z "${reason// }" ]]; then
    echo "Change ticket and reason are mandatory for destructive action '$action'." >&2
    return 1
  fi
  prompt_yes_no "Confirm destructive action '$action' with ticket '$ticket' and reason '$reason'?"
}

enforce_ssh_private_key_permissions() {
  local path="$1"
  local mode
  mode="$(file_mode_octal "$path")"
  if [[ "$mode" == "600" ]]; then
    return 0
  fi
  if offer_fix_then_execute "SSH private key '$path' has mode '${mode:-unknown}', expected '600'." "chmod 600 '$path'"; then
    [[ "$(file_mode_octal "$path")" == "600" ]]
    return
  fi
  return 1
}

read_required_value() {
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
    echo "$prompt"
    echo "  Required because: $reason"
    echo "  Will be written to: $target_path"
    if [[ "$secret" == "true" ]]; then
      if [[ "$input_device" != "/dev/tty" ]]; then
        echo "Interactive terminal is required to capture secret input securely." >&2
        echo "Run this command in an interactive shell and retry." >&2
        return 1
      fi
      echo "  Waiting for secure input (hidden)..."
      read -r -s value <"$input_device"
      printf '\n'
    else
      read -r value <"$input_device"
    fi

    if [[ -z "${value// }" ]]; then
      echo "This value is mandatory. Execution will not continue without it." >&2
      continue
    fi

    printf '%s' "$value"
    return 0
  done
}

read_choice() {
  local prompt="$1"
  local reason="$2"
  local target_path="$3"
  shift 3
  local -a choices=("$@")
  local value=""

  while true; do
    echo "$prompt"
    echo "  Required because: $reason"
    echo "  Will be written to: $target_path"
    echo "  Allowed values: ${choices[*]}"
    read -r value
    for choice in "${choices[@]}"; do
      if [[ "$value" == "$choice" ]]; then
        printf '%s' "$value"
        return 0
      fi
    done
    echo "Invalid value '$value'. Choose one of: ${choices[*]}" >&2
  done
}

validate_hostname_or_ip() {
  local value="$1"
  if [[ "$value" =~ ^([a-zA-Z0-9][-a-zA-Z0-9]*\.)*[a-zA-Z0-9][-a-zA-Z0-9]*$ ]]; then
    return 0
  fi
  if [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    return 0
  fi
  return 1
}

read_hostname_or_ip() {
  local prompt="$1"
  local reason="$2"
  local target_path="$3"
  local value=""

  while true; do
    value="$(read_required_value "$prompt" "$reason" "$target_path")"
    if validate_hostname_or_ip "$value"; then
      printf '%s' "$value"
      return 0
    fi
    echo "Value '$value' is not a valid hostname or IPv4 address." >&2
  done
}

read_existing_file() {
  local prompt="$1"
  local reason="$2"
  local target_path="$3"
  local value=""

  while true; do
    value="$(read_required_value "$prompt" "$reason" "$target_path")"
    if [[ -f "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
    echo "File '$value' was not found." >&2
  done
}

read_existing_private_key_file() {
  local prompt="$1"
  local reason="$2"
  local target_path="$3"
  local value
  while true; do
    value="$(read_existing_file "$prompt" "$reason" "$target_path")"
    if enforce_ssh_private_key_permissions "$value"; then
      printf '%s' "$value"
      return 0
    fi
    echo "SSH key permissions are mandatory. Fix is required to continue." >&2
  done
}

save_yaml_map() {
  local output_path="$1"
  shift

  {
    echo "---"
    while (($#)); do
      local key="$1"
      local value="$2"
      shift 2
      value="${value//\'/\'\'}"
      printf "%s: '%s'\n" "$key" "$value"
    done
  } >"$output_path"
  chmod 600 "$output_path"
}

write_runtime_inventory() {
  local output_path="$1"
  local environment="$2"
  local ssh_user="$3"
  local ssh_key="$4"
  local app_host="$5"
  local db_host="$6"

  cat >"$output_path" <<EOF
---
all:
  vars:
    ansible_user: ${ssh_user}
    ansible_ssh_private_key_file: ${ssh_key}
    environment_name: ${environment}
  children:
    glpi_app:
      hosts:
        stg-app:
          ansible_host: ${app_host}
    glpi_db:
      hosts:
        stg-db:
          ansible_host: ${db_host}
EOF
}

export_runtime_inventory_if_present() {
  local environment="$1"
  local runtime_inventory="$SCRIPT_ROOT/../.runtime/$environment/inventory.runtime.yml"
  if [[ -f "$runtime_inventory" ]]; then
    export ANSIBLE_RUNTIME_INVENTORY="$runtime_inventory"
  fi
}

runtime_env_dir() {
  local environment="$1"
  echo "$SCRIPT_ROOT/../.runtime/$environment"
}

runtime_inventory_path() {
  local environment="$1"
  echo "$(runtime_env_dir "$environment")/inventory.runtime.yml"
}

runtime_public_path() {
  local environment="$1"
  echo "$(runtime_env_dir "$environment")/public.runtime.yml"
}

runtime_override_path() {
  local environment="$1"
  echo "$(runtime_env_dir "$environment")/overrides.runtime.yml"
}

runtime_secret_path() {
  local environment="$1"
  echo "$(runtime_env_dir "$environment")/secrets.yml"
}

runtime_app_path() {
  local environment="$1"
  echo "$(runtime_env_dir "$environment")/app.runtime.yml"
}

config_file_path() {
  local environment="$1"
  echo "$SCRIPT_ROOT/../config/$environment.env"
}

config_example_path() {
  echo "$SCRIPT_ROOT/../config/.env.example"
}

require_python_yaml_support() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to render runtime files." >&2
    return 1
  fi
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "python3-yaml support is required. Install PyYAML or the OS Python YAML package." >&2
    return 1
  fi
}

render_product_config() {
  local environment="$1"
  local mode="$2"
  local config_path
  config_path="$(config_file_path "$environment")"
  require_runtime_file "$config_path" "product configuration file"
  require_python_yaml_support
  python3 "$COMMON_LIB_ROOT/render_product_config.py" --config "$config_path" --mode "$mode"
}

read_product_config_value() {
  local environment="$1"
  local dotted_key="$2"
  local config_path
  config_path="$(config_file_path "$environment")"
  require_runtime_file "$config_path" "product configuration file"
  python3 "$COMMON_LIB_ROOT/render_product_config.py" --config "$config_path" --mode get --key "$dotted_key"
}

materialize_runtime_from_config() {
  local environment="$1"
  local public_path
  local inventory_path
  local override_path
  public_path="$(runtime_public_path "$environment")"
  inventory_path="$(runtime_inventory_path "$environment")"
  override_path="$(runtime_override_path "$environment")"
  ensure_runtime_foundation "$environment"
  render_product_config "$environment" public-runtime >"$public_path"
  chmod 600 "$public_path"
  render_product_config "$environment" inventory >"$inventory_path"
  chmod 600 "$inventory_path"
  if [[ ! -f "$override_path" ]]; then
    cat >"$override_path" <<'EOF'
{}
EOF
  fi
  chmod 600 "$override_path"
  cp "$public_path" "$(runtime_app_path "$environment")"
}

ensure_runtime_override_file() {
  local environment="$1"
  local override_path
  override_path="$(runtime_override_path "$environment")"
  ensure_runtime_foundation "$environment"
  if [[ ! -f "$override_path" ]]; then
    cat >"$override_path" <<'EOF'
{}
EOF
  fi
  if ! yaml_file_is_dictionary "$override_path"; then
    echo "Invalid override runtime YAML detected at '$override_path'. Rewriting as empty map '{}'."
    cat >"$override_path" <<'EOF'
{}
EOF
  fi
  chmod 600 "$override_path"
}

yaml_file_is_dictionary() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    return 1
  fi
  require_python_yaml_support
  python3 - "$file_path" <<'PY'
import sys
import yaml
from pathlib import Path

path = Path(sys.argv[1])
data = yaml.safe_load(path.read_text(encoding="utf-8"))
if isinstance(data, dict):
    sys.exit(0)
sys.exit(1)
PY
}

read_yaml_top_level_value() {
  local file_path="$1"
  local key_name="$2"
  if [[ ! -f "$file_path" ]]; then
    return 1
  fi
  require_python_yaml_support
  python3 - "$file_path" "$key_name" <<'PY'
import sys
import yaml
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
value = data.get(key, "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

update_yaml_top_level_value() {
  local file_path="$1"
  local key_name="$2"
  local value="$3"
  require_runtime_file "$file_path" "yaml file"
  require_python_yaml_support
  python3 - "$file_path" "$key_name" "$value" <<'PY'
import sys
import yaml
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
if value == "true":
    parsed = True
elif value == "false":
    parsed = False
else:
    parsed = value
data[key] = parsed
path.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False), encoding="utf-8")
PY
  chmod 600 "$file_path"
}

ensure_secret_keys() {
  local environment="$1"
  local secret_path
  local glpi_db_password glpi_db_root_password glpi_db_managed_admin_password mysqld_exporter_password db_deployment_mode
  local grafana_admin_password glpi_metrics_db_password
  local monitoring_grafana_enabled monitoring_glpi_custom_metrics_enabled monitoring_mysqld_exporter_enabled
  local auth_saml_x509_certificate ldap_bind_password oidc_client_secret
  secret_path="$(runtime_secret_path "$environment")"
  ensure_runtime_foundation "$environment"
  db_deployment_mode="$(resolve_database_deployment_mode_for_environment "$environment")"
  [[ "$db_deployment_mode" == "invalid" ]] && db_deployment_mode="self_hosted"

  glpi_db_password="$(read_product_config_value "$environment" "DATABASE_PASSWORD" || true)"
  glpi_db_root_password="$(read_product_config_value "$environment" "DATABASE_ROOT_PASSWORD" || true)"
  glpi_db_managed_admin_password="$(read_product_config_value "$environment" "DATABASE_MANAGED_ADMIN_PASSWORD" || true)"
  mysqld_exporter_password="$(read_product_config_value "$environment" "MONITORING_MYSQLD_EXPORTER_PASSWORD" || true)"
  monitoring_mysqld_exporter_enabled="$(read_product_config_value "$environment" "monitoring.exporters.mysqld.enabled" || true)"
  monitoring_grafana_enabled="$(read_product_config_value "$environment" "monitoring.grafana.enabled" || true)"
  monitoring_glpi_custom_metrics_enabled="$(read_product_config_value "$environment" "monitoring.glpi_custom_metrics.enabled" || true)"

  # Auth secrets are runtime-only and must not depend on config/<environment>.env.
  auth_saml_x509_certificate=""
  ldap_bind_password=""
  oidc_client_secret=""
  grafana_admin_password=""
  glpi_metrics_db_password=""
  if [[ -f "$secret_path" ]]; then
    auth_saml_x509_certificate="$(read_yaml_top_level_value "$secret_path" "auth_saml_x509_certificate" || true)"
    ldap_bind_password="$(read_yaml_top_level_value "$secret_path" "ldap_bind_password" || true)"
    oidc_client_secret="$(read_yaml_top_level_value "$secret_path" "oidc_client_secret" || true)"
    if [[ -z "${mysqld_exporter_password// }" ]]; then
      mysqld_exporter_password="$(read_yaml_top_level_value "$secret_path" "mysqld_exporter_password" || true)"
    fi
    grafana_admin_password="$(read_yaml_top_level_value "$secret_path" "grafana_admin_password" || true)"
    glpi_metrics_db_password="$(read_yaml_top_level_value "$secret_path" "glpi_metrics_db_password" || true)"
  fi

  if [[ -z "${glpi_db_password// }" ]]; then
    echo "Missing required config key: DATABASE_PASSWORD" >&2
    echo "Purpose: secret password for GLPI database user" >&2
    echo "Used by: database provisioning and application connectivity" >&2
    exit 1
  fi
  if [[ "$db_deployment_mode" == "self_hosted" && -z "${glpi_db_root_password// }" ]]; then
    echo "Missing required config key: DATABASE_ROOT_PASSWORD" >&2
    echo "Purpose: root password for MariaDB administrative operations" >&2
    echo "Used by: schema creation, grants, and hardening" >&2
    exit 1
  fi
  if [[ "$db_deployment_mode" == "self_hosted" && "$monitoring_mysqld_exporter_enabled" == "true" && -z "${mysqld_exporter_password// }" ]]; then
    mysqld_exporter_password="$(read_required_value \
      "Enter mysqld exporter database password for environment '$environment':" \
      "least-privilege SQL account used by mysqld_exporter; it must stay outside config/<environment>.env" \
      "$secret_path" \
      "true")"
  fi
  if [[ "$monitoring_grafana_enabled" == "true" && -z "${grafana_admin_password// }" ]]; then
    grafana_admin_password="$(read_required_value \
      "Enter Grafana admin password for environment '$environment':" \
      "Grafana local administrator bootstrap password; it must stay outside config/<environment>.env" \
      "$secret_path" \
      "true")"
  fi
  if [[ "$monitoring_glpi_custom_metrics_enabled" == "true" && -z "${glpi_metrics_db_password// }" ]]; then
    glpi_metrics_db_password="$(read_required_value \
      "Enter GLPI metrics database password for environment '$environment':" \
      "least-privilege SQL account used by the local node_exporter textfile metrics script" \
      "$secret_path" \
      "true")"
  fi

  save_yaml_map "$secret_path" \
    glpi_db_password "$glpi_db_password" \
    glpi_db_root_password "$glpi_db_root_password" \
    glpi_db_managed_admin_password "$glpi_db_managed_admin_password" \
    mysqld_exporter_password "$mysqld_exporter_password" \
    grafana_admin_password "$grafana_admin_password" \
    glpi_metrics_db_password "$glpi_metrics_db_password" \
    auth_saml_x509_certificate "$auth_saml_x509_certificate" \
    ldap_bind_password "$ldap_bind_password" \
    oidc_client_secret "$oidc_client_secret"
}

require_runtime_file() {
  local path="$1"
  local description="$2"
  if [[ ! -f "$path" ]]; then
    echo "Missing ${description}: $path" >&2
    exit 1
  fi
}

write_app_runtime() {
  local output_path="$1"
  local glpi_version="$2"
  local app_host="$3"
  local tls_mode="$4"
  local tls_common_name="$5"
  local local_cert_path="$6"
  local local_key_path="$7"
  local use_tls="false"

  if [[ "$tls_mode" != "none" ]]; then
    use_tls="true"
  fi

  cat >"$output_path" <<EOF
---
glpi_version: "${glpi_version}"
glpi_download_url: "https://github.com/glpi-project/glpi/releases/download/${glpi_version}/glpi-${glpi_version}.tgz"
glpi_release_dir: "/usr/share/glpi-${glpi_version}"
glpi_domain: "${app_host}"
glpi_use_tls: ${use_tls}
glpi_tls_mode: "${tls_mode}"
glpi_tls_common_name: "${tls_common_name}"
glpi_tls_provided_local_cert_path: "${local_cert_path}"
glpi_tls_provided_local_key_path: "${local_key_path}"
EOF
}

invoke_ansible() {
  local environment="$1"
  local tags="$2"
  shift 2

  assert_command "ansible-playbook"
  local inventory="${ANSIBLE_RUNTIME_INVENTORY:-$(runtime_inventory_path "$environment")}"
  require_runtime_file "$inventory" "runtime inventory for environment '$environment'"
  local playbook="$SCRIPT_ROOT/../ansible/site.yml"
  local args=("-i" "$inventory" "$playbook")

  if [[ -n "$tags" ]]; then
    args+=("--tags" "$tags")
  fi

  for file in "$@"; do
    args+=("--extra-vars" "@$file")
  done

  echo "Executing command: ansible-playbook ${args[*]}"
  run_with_heartbeat 30 "ansible-playbook is still running (tags=${tags:-all})" ansible-playbook "${args[@]}"
}

run_with_heartbeat() {
  local interval_seconds="$1"
  local heartbeat_message="$2"
  shift 2

  "$@" &
  local cmd_pid=$!
  local elapsed=0

  while kill -0 "$cmd_pid" >/dev/null 2>&1; do
    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
    if kill -0 "$cmd_pid" >/dev/null 2>&1; then
      echo "[heartbeat] ${heartbeat_message}. elapsed=${elapsed}s"
    fi
  done

  wait "$cmd_pid"
}

preflight_print_result() {
  local level="$1"
  local status="$2"
  local message="$3"
  printf '[%s] [%s] %s\n' "$level" "$status" "$message"
}

preflight_items_file_path() {
  local environment="$1"
  echo "$(runtime_state_dir "$environment")/.precheck-items.tsv"
}

preflight_report_latest_path() {
  local environment="$1"
  echo "$(runtime_state_dir "$environment")/precheck-report-latest.yml"
}

preflight_report_markdown_path() {
  local environment="$1"
  echo "$(runtime_evidence_dir "$environment")/precheck-report-latest.md"
}

append_precheck_item() {
  local environment="$1"
  local item="$2"
  local category="$3"
  local applicability="$4"
  local obligation="$5"
  local reason="$6"
  local validation="$7"
  local autofix="$8"
  local block="$9"
  local status="${10}"
  local suggested_action="${11}"
  local items_file
  items_file="$(preflight_items_file_path "$environment")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$item" "$category" "$applicability" "$obligation" "$reason" "$validation" "$autofix" "$block" "$status" "$suggested_action" "$(date -u +%FT%TZ)" >>"$items_file"
}

finalize_precheck_reports() {
  local environment="$1"
  local mandatory_failures="$2"
  local optional_failures="$3"
  local items_file report_path report_md_path timestamped_report
  items_file="$(preflight_items_file_path "$environment")"
  report_path="$(preflight_report_latest_path "$environment")"
  report_md_path="$(preflight_report_markdown_path "$environment")"
  timestamped_report="$(runtime_state_dir "$environment")/precheck-report-$(date -u +%Y%m%dT%H%M%SZ).yml"

  {
    echo "---"
    echo "environment: '$environment'"
    echo "generated_at: '$(date -u +%FT%TZ)'"
    echo "mandatory_failures: $mandatory_failures"
    echo "optional_failures: $optional_failures"
    echo "overall_status: '$([[ "$mandatory_failures" -eq 0 ]] && echo pass || echo fail)'"
    echo "items:"
    while IFS=$'\t' read -r item category applicability obligation reason validation autofix block status suggested_action checked_at; do
      [[ -z "${item// }" ]] && continue
      echo "  - item: '$item'"
      echo "    category: '$category'"
      echo "    applicability: '$applicability'"
      echo "    obligation: '$obligation'"
      echo "    reason: '$reason'"
      echo "    validation: '$validation'"
      echo "    auto_fix: '$autofix'"
      echo "    block_on_failure: '$block'"
      echo "    status: '$status'"
      echo "    suggested_action: '$suggested_action'"
      echo "    checked_at: '$checked_at'"
    done <"$items_file"
  } >"$report_path"
  cp "$report_path" "$timestamped_report"
  chmod 600 "$report_path" "$timestamped_report"

  {
    echo "# Precheck Report"
    echo
    echo "- Environment: \`$environment\`"
    echo "- Generated at (UTC): \`$(date -u +%FT%TZ)\`"
    echo "- Overall status: \`$([[ "$mandatory_failures" -eq 0 ]] && echo PASS || echo FAIL)\`"
    echo "- Mandatory failures: \`$mandatory_failures\`"
    echo "- Optional findings: \`$optional_failures\`"
    echo
    echo "| Item | Category | Applicability | Obligation | Status | Block | Suggested action |"
    echo "|---|---|---|---|---|---|---|"
    while IFS=$'\t' read -r item category applicability obligation reason validation autofix block status suggested_action checked_at; do
      [[ -z "${item// }" ]] && continue
      echo "| $item | $category | $applicability | $obligation | $status | $block | $suggested_action |"
    done <"$items_file"
  } >"$report_md_path"
  chmod 600 "$report_md_path"
}

os_release_file_path() {
  printf '%s\n' "${GLPI_OS_RELEASE_FILE:-/etc/os-release}"
}

os_release_value() {
  local key="$1"
  local os_release_file
  os_release_file="$(os_release_file_path)"
  if [[ ! -f "$os_release_file" ]]; then
    return 1
  fi
  awk -F= -v key="$key" '
    $1 == key {
      value = $0
      sub(/^[^=]*=/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "$os_release_file"
}

os_release_token_matches() {
  local value="$1"
  local expected="$2"
  local token
  for token in $value; do
    if [[ "$token" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

platform_family() {
  local distro_id distro_like
  distro_id="$(os_release_value "ID" | tr '[:upper:]' '[:lower:]' || true)"
  distro_like="$(os_release_value "ID_LIKE" | tr '[:upper:]' '[:lower:]' || true)"

  case "$distro_id" in
    ubuntu|debian)
      echo "debian"
      return 0
      ;;
    rocky|rhel|almalinux|centos)
      echo "rhel"
      return 0
      ;;
  esac

  if os_release_token_matches "$distro_like" "debian" || os_release_token_matches "$distro_like" "ubuntu"; then
    echo "debian"
    return 0
  fi
  if os_release_token_matches "$distro_like" "rhel" || os_release_token_matches "$distro_like" "centos"; then
    echo "rhel"
    return 0
  fi

  echo "unknown"
}

platform_human_name() {
  local distro_id distro_version distro_name
  distro_id="$(os_release_value "ID" || true)"
  distro_version="$(os_release_value "VERSION_ID" || true)"
  distro_name="$(os_release_value "PRETTY_NAME" || true)"
  if [[ -n "${distro_name// }" ]]; then
    echo "$distro_name"
    return 0
  fi
  echo "${distro_id:-unknown} ${distro_version:-unknown}"
}

platform_supported() {
  if [[ ! -f "$(os_release_file_path)" ]]; then
    return 1
  fi
  local distro_id distro_version distro_major family
  distro_id="$(os_release_value "ID" | tr '[:upper:]' '[:lower:]' || true)"
  distro_version="$(os_release_value "VERSION_ID" || true)"
  distro_major="${distro_version%%.*}"
  family="$(platform_family)"

  if [[ "$distro_id" == "ubuntu" && "$distro_version" == 24.04* ]]; then
    return 0
  fi
  if [[ "$family" == "rhel" && "$distro_major" == "9" ]]; then
    return 0
  fi

  return 1
}

platform_package_manager() {
  case "$(platform_family)" in
    debian) echo "apt" ;;
    rhel) echo "dnf" ;;
    *) echo "unknown" ;;
  esac
}

package_install_action() {
  local package_name="$1"
  case "$(platform_package_manager)" in
    apt) echo "apt install ${package_name}" ;;
    dnf) echo "dnf install ${package_name}" ;;
    yum) echo "yum install ${package_name}" ;;
    *) echo "manual install ${package_name}" ;;
  esac
}

package_install_command() {
  local package_name="$1"
  case "$(platform_package_manager)" in
    apt)
      if command -v sudo >/dev/null 2>&1; then
        echo "sudo apt-get update && sudo apt-get install -y ${package_name}"
      else
        echo "apt-get update && apt-get install -y ${package_name}"
      fi
      ;;
    dnf)
      if command -v sudo >/dev/null 2>&1; then
        echo "sudo dnf install -y ${package_name}"
      else
        echo "dnf install -y ${package_name}"
      fi
      ;;
    yum)
      if command -v sudo >/dev/null 2>&1; then
        echo "sudo yum install -y ${package_name}"
      else
        echo "yum install -y ${package_name}"
      fi
      ;;
    *)
      echo ""
      ;;
  esac
}

ssh_public_key_path_for_private_key() {
  local private_key="$1"
  if [[ "$private_key" == *.pub ]]; then
    echo "$private_key"
    return
  fi
  echo "${private_key}.pub"
}

ensure_ssh_key_material_for_environment() {
  local environment="$1"
  local topology_mode="$2"
  local execution_mode="$3"
  local key_path="$4"
  local ssh_user="$5"
  local app_host="$6"
  local db_host="$7"
  local db_deployment_mode="${8:-self_hosted}"

  local resolved_key_path public_key_path must_check_connectivity
  if [[ "$execution_mode" != "ssh" ]]; then
    return 0
  fi
  resolved_key_path="$(expand_home_path "$key_path")"
  public_key_path="$(ssh_public_key_path_for_private_key "$resolved_key_path")"
  must_check_connectivity="false"
  [[ "$topology_mode" == "dual-server" ]] && must_check_connectivity="true"

  if [[ ! -f "$resolved_key_path" ]]; then
    return 1
  fi
  if ! enforce_ssh_private_key_permissions "$resolved_key_path"; then
    return 1
  fi
  if [[ ! -f "$public_key_path" ]]; then
    return 1
  fi

  if [[ "$must_check_connectivity" == "true" ]]; then
    if ! command -v ssh >/dev/null 2>&1; then
      return 1
    fi
    if ! ssh -o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=accept-new -i "$resolved_key_path" "${ssh_user}@${app_host}" "echo ok" >/dev/null 2>&1; then
      return 1
    fi
    if [[ "$db_deployment_mode" != "managed" ]]; then
      if ! ssh -o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=accept-new -i "$resolved_key_path" "${ssh_user}@${db_host}" "echo ok" >/dev/null 2>&1; then
        return 1
      fi
    fi
  fi
  return 0
}

package_for_command() {
  local command_name="$1"
  case "$(platform_family)" in
    rhel)
      case "$command_name" in
        ansible|ansible-playbook|ansible-inventory) echo "ansible-core" ;;
        git) echo "git" ;;
        python3) echo "python3" ;;
        ssh) echo "openssh-clients" ;;
        bash) echo "bash" ;;
        mysql) echo "mysql" ;;
        *) echo "" ;;
      esac
      ;;
    *)
      case "$command_name" in
        ansible|ansible-playbook|ansible-inventory) echo "ansible" ;;
        git) echo "git" ;;
        python3) echo "python3" ;;
        ssh) echo "openssh-client" ;;
        bash) echo "bash" ;;
        mysql) echo "mariadb-client" ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

package_for_python_yaml() {
  case "$(platform_family)" in
    rhel) echo "python3-PyYAML" ;;
    *) echo "python3-yaml" ;;
  esac
}

required_ansible_modules_available() {
  local -a required_modules=(
    "community.mysql.mysql_db"
    "community.mysql.mysql_query"
    "community.mysql.mysql_user"
  )
  local -a missing_modules=()
  local module

  if ! command -v ansible-doc >/dev/null 2>&1; then
    echo "ansible-doc command not found"
    return 1
  fi

  for module in "${required_modules[@]}"; do
    if ! ansible-doc -t module "$module" >/dev/null 2>&1; then
      missing_modules+=("$module")
    fi
  done

  if ((${#missing_modules[@]} > 0)); then
    printf 'missing modules: %s\n' "${missing_modules[*]}"
    return 1
  fi

  return 0
}

php_cli_package_for_platform() {
  local php_version="$1"
  case "$(platform_family)" in
    rhel) echo "php-cli" ;;
    *) echo "php${php_version}-cli" ;;
  esac
}

php_fpm_package_for_platform() {
  local php_version="$1"
  case "$(platform_family)" in
    rhel) echo "php-fpm" ;;
    *) echo "php${php_version}-fpm" ;;
  esac
}

php_extension_package_for_platform() {
  local extension_name="$1"
  local php_version="$2"
  case "$(platform_family)" in
    rhel)
      case "$extension_name" in
        mysqli|mysqlnd) echo "php-mysqlnd" ;;
        redis) echo "php-pecl-redis" ;;
        apcu) echo "php-pecl-apcu" ;;
        *) echo "php-${extension_name}" ;;
      esac
      ;;
    *)
      echo "php${php_version}-${extension_name}"
      ;;
  esac
}

install_command_platform() {
  local command_name="$1"
  local package_name="$2"
  local install_cmd

  install_cmd="$(package_install_command "$package_name")"
  if [[ -z "${install_cmd// }" ]]; then
    return 1
  fi

  echo "Trying to install '${command_name}' from package '${package_name}'..."
  if bash -lc "$install_cmd"; then
    return 0
  fi
  return 1
}

prompt_install_missing_command() {
  local level="$1"
  local command_name="$2"
  local package_name="$3"
  local answer=""

  if [[ "$PREFLIGHT_AUTO_INSTALL" == "always" ]]; then
    answer="y"
  else
    echo "Command '${command_name}' is missing (${level})."
    if prompt_yes_no "Install now on this $(platform_family) host using package '${package_name}'?"; then
      answer="y"
    else
      answer="n"
    fi
  fi

  if [[ "$answer" != "y" ]]; then
    return 1
  fi

  if install_command_platform "$command_name" "$package_name"; then
    if command -v "$command_name" >/dev/null 2>&1; then
      preflight_print_result "$level" "ok" "command '$command_name' installed successfully"
      return 0
    fi
  fi

  echo "Automatic installation failed for '${command_name}'." >&2
  echo "Manual remediation ($(platform_family)):" >&2
  echo "  $(package_install_command "$package_name")" >&2
  return 1
}

check_or_install_command() {
  local level="$1"
  local command_name="$2"
  local package_name="$3"

  if command -v "$command_name" >/dev/null 2>&1; then
    preflight_print_result "$level" "ok" "command '$command_name' found"
    return 0
  fi

  preflight_print_result "$level" "fail" "command '$command_name' not found"
  if [[ -n "$package_name" ]] && prompt_install_missing_command "$level" "$command_name" "$package_name"; then
    return 0
  fi
  return 1
}

check_or_install_python_yaml_support() {
  local level="$1"
  local answer=""
  local package_name
  package_name="$(package_for_python_yaml)"
  if ! command -v python3 >/dev/null 2>&1; then
    preflight_print_result "$level" "fail" "python3 command not found for python3-yaml validation"
    return 1
  fi
  if python3 -c "import yaml" >/dev/null 2>&1; then
    preflight_print_result "$level" "ok" "python3-yaml module found"
    return 0
  fi

  preflight_print_result "$level" "fail" "python3-yaml module not found"
  if [[ "$PREFLIGHT_AUTO_INSTALL" == "always" ]]; then
    answer="y"
  else
    echo "python3-yaml module is missing (${level})."
    if prompt_yes_no "Install now on this $(platform_family) host using package '${package_name}'?"; then
      answer="y"
    else
      answer="n"
    fi
  fi

  if [[ "$answer" != "y" ]]; then
    return 1
  fi

  if install_command_platform "python3-yaml" "$package_name"; then
    if python3 -c "import yaml" >/dev/null 2>&1; then
      preflight_print_result "$level" "ok" "python3-yaml module installed successfully"
      return 0
    fi
  fi

  echo "Automatic installation failed for 'python3-yaml'." >&2
  echo "Manual remediation ($(platform_family)):" >&2
  echo "  $(package_install_command "$package_name")" >&2
  return 1
}

resolve_php_version_for_environment() {
  local environment="$1"
  local configured_fpm_service php_version
  configured_fpm_service="$(read_product_config_value "$environment" "php_fpm.service_name" || true)"
  [[ -z "${configured_fpm_service// }" ]] && configured_fpm_service="$(read_product_config_value "$environment" "PHP_FPM_SERVICE_NAME" || true)"
  if [[ "$configured_fpm_service" =~ php([0-9]+\.[0-9]+)-fpm ]]; then
    php_version="${BASH_REMATCH[1]}"
    echo "$php_version"
    return 0
  fi
  echo "8.3"
}

php_extension_enabled() {
  local extension_name="$1"
  local php_bin="${2:-php}"
  if ! command -v "$php_bin" >/dev/null 2>&1; then
    return 1
  fi
  "$php_bin" -m 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -Fx "$extension_name" >/dev/null 2>&1
}

package_installed() {
  local package_name="$1"
  case "$(platform_family)" in
    rhel) rpm -q "$package_name" >/dev/null 2>&1 ;;
    *) dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed" ;;
  esac
}

service_exists() {
  local service_name="$1"
  systemctl list-unit-files "$service_name" --no-legend 2>/dev/null | awk 'NF {print $1}' | grep -Fx "$service_name" >/dev/null 2>&1
}

ensure_php_cli_available() {
  local php_version="$1"
  local cli_package
  cli_package="$(php_cli_package_for_platform "$php_version")"
  if command -v php >/dev/null 2>&1; then
    return 0
  fi
  echo "PHP CLI binary not found. Installing ${cli_package} before extension validation." >&2
  if ! install_command_platform "$cli_package" "$cli_package"; then
    return 1
  fi
  command -v php >/dev/null 2>&1
}

auto_remediate_php_extension() {
  local extension_name="$1"
  local php_version="$2"
  local fpm_service="$3"
  local extension_package cli_package fpm_package
  local enable_cli_cmd enable_fpm_cmd restart_fpm_cmd
  extension_package="$(php_extension_package_for_platform "$extension_name" "$php_version")"
  cli_package="$(php_cli_package_for_platform "$php_version")"
  fpm_package="$(php_fpm_package_for_platform "$php_version")"

  if ! ensure_php_cli_available "$php_version"; then
    echo "PHP CLI binary not found and automatic installation failed." >&2
    return 1
  fi

  if ! package_installed "$cli_package"; then
    echo "PHP CLI package ${cli_package} not installed. Installing package." >&2
    install_command_platform "$cli_package" "$cli_package" || return 1
  fi

  if ! package_installed "$extension_package"; then
    echo "PHP extension package ${extension_package} not installed. Installing package." >&2
    install_command_platform "$extension_package" "$extension_package" || return 1
  fi

  if [[ "$(platform_family)" == "rhel" ]]; then
    if service_exists "$fpm_service"; then
      if command -v sudo >/dev/null 2>&1; then
        restart_fpm_cmd="sudo systemctl restart '${fpm_service}'"
      else
        restart_fpm_cmd="systemctl restart '${fpm_service}'"
      fi
      bash -lc "$restart_fpm_cmd" || return 1
    fi
    php_extension_enabled "$extension_name" "php"
    return $?
  fi

  if ! command -v phpenmod >/dev/null 2>&1; then
    echo "phpenmod command not found; unable to enable PHP extension automatically." >&2
    return 1
  fi

  if command -v sudo >/dev/null 2>&1; then
    enable_cli_cmd="sudo phpenmod -v '${php_version}' -s cli '${extension_name}'"
    enable_fpm_cmd="sudo phpenmod -v '${php_version}' -s fpm '${extension_name}'"
    restart_fpm_cmd="sudo systemctl restart '${fpm_service}'"
  else
    enable_cli_cmd="phpenmod -v '${php_version}' -s cli '${extension_name}'"
    enable_fpm_cmd="phpenmod -v '${php_version}' -s fpm '${extension_name}'"
    restart_fpm_cmd="systemctl restart '${fpm_service}'"
  fi

  if ! php_extension_enabled "$extension_name" "php"; then
    echo "PHP extension ${extension_name} package is installed but not enabled for cli. Enabling with phpenmod." >&2
    bash -lc "$enable_cli_cmd" || return 1
  fi

  if service_exists "$fpm_service"; then
    if ! package_installed "$fpm_package"; then
      echo "PHP-FPM package ${fpm_package} not installed. Installing package." >&2
      install_command_platform "$fpm_package" "$fpm_package" || return 1
    fi
    if ! bash -lc "$enable_fpm_cmd"; then
      return 1
    fi
    if ! bash -lc "$restart_fpm_cmd"; then
      echo "Failed to restart ${fpm_service} after enabling ${extension_name}." >&2
      return 1
    fi
  else
    echo "PHP-FPM service ${fpm_service} not found. Skipping FPM restart." >&2
  fi

  if ! service_exists "apache2.service"; then
    echo "Apache service not found. Skipping Apache restart." >&2
  fi

  php_extension_enabled "$extension_name" "php"
}

check_or_install_php_extension() {
  local level="$1"
  local extension_name="$2"
  local php_version="$3"
  local fpm_service="$4"
  local package_name
  local answer=""
  local remediation_answer=""
  package_name="$(php_extension_package_for_platform "$extension_name" "$php_version")"

  if ! ensure_php_cli_available "$php_version"; then
    preflight_print_result "$level" "fail" "php cli not found"
    return 1
  fi

  if php_extension_enabled "$extension_name" "php"; then
    preflight_print_result "$level" "ok" "php extension '$extension_name' found"
    return 0
  fi

  preflight_print_result "$level" "fail" "php extension '$extension_name' not found"
  if [[ "$PREFLIGHT_AUTO_INSTALL" == "always" ]]; then
    answer="y"
  else
    echo "PHP extension '$extension_name' is missing (${level})."
    if prompt_yes_no "Install now on this $(platform_family) host using package '${package_name}'?"; then
      answer="y"
    else
      answer="n"
    fi
  fi

  if [[ "$answer" != "y" ]]; then
    return 1
  fi

  if install_command_platform "$package_name" "$package_name"; then
    if php_extension_enabled "$extension_name" "php"; then
      preflight_print_result "$level" "ok" "php extension '$extension_name' installed successfully"
      return 0
    fi
  fi

  echo "Automatic installation failed for PHP extension '${extension_name}'." >&2
  echo "Manual remediation ($(platform_family)):" >&2
  echo "  $(package_install_command "$package_name")" >&2

  if [[ -t 0 || -r /dev/tty ]]; then
    if prompt_yes_no "Try automatic remediation now (phpenmod + php-fpm restart) for '${extension_name}'?"; then
      remediation_answer="y"
    else
      remediation_answer="n"
    fi
    if [[ "$remediation_answer" == "y" ]]; then
      if auto_remediate_php_extension "$extension_name" "$php_version" "$fpm_service"; then
        preflight_print_result "$level" "ok" "php extension '$extension_name' found after automatic remediation"
        return 0
      fi
      echo "PHP extension ${extension_name} is still not loaded after remediation." >&2
    fi
  fi

  return 1
}

normalize_bool_value() {
  local value="$1"
  local default_value="$2"
  case "$value" in
    true|false) echo "$value" ;;
    *)
      if [[ -n "$default_value" ]]; then
        echo "$default_value"
      else
        echo "false"
      fi
      ;;
  esac
}

glpi_db_compatibility_report() {
  local glpi_version="$1"
  local db_version_output="$2"
  python3 - "$glpi_version" "$db_version_output" <<'PY'
import re
import sys

glpi_version = sys.argv[1]
db_output = sys.argv[2]


def version_tuple(value):
    parts = [int(part) for part in re.findall(r"\d+", value)]
    return tuple((parts + [0, 0, 0])[:3])


def emit(key, value):
    print(f"{key}={value}")


major_match = re.search(r"\d+", glpi_version)
glpi_major = int(major_match.group(0)) if major_match else 0
lower_output = db_output.lower()
engine = "mariadb" if "mariadb" in lower_output else "mysql"
version_match = re.search(r"\d+\.\d+(?:\.\d+)?", db_output)
detected_version = version_match.group(0) if version_match else "unknown"

if glpi_major >= 11:
    required = {"mysql": "8.0", "mariadb": "10.6"}
    requirement = "GLPI 11 requires MySQL >= 8.0 or MariaDB >= 10.6."
elif glpi_major == 10:
    required = {"mysql": "5.7", "mariadb": "10.2"}
    requirement = "GLPI 10 requires MySQL >= 5.7 or MariaDB >= 10.2."
else:
    required = {}
    requirement = "Only GLPI 10 and GLPI 11 database compatibility rules are defined by this kit."

minimum = required.get(engine, "")
status = "fail"
if minimum and detected_version != "unknown":
    status = "pass" if version_tuple(detected_version) >= version_tuple(minimum) else "fail"

if not minimum:
    message = f"Unsupported GLPI version family for compatibility validation: {glpi_version}."
elif detected_version == "unknown":
    message = f"Unable to parse database server version from: {db_output}."
elif status == "pass":
    message = f"Managed DB is compatible: GLPI {glpi_version}, {engine} {detected_version}, minimum {minimum}."
else:
    message = f"Blocking deployment before app mutation: GLPI {glpi_version} is configured, but managed DB reports {engine} {detected_version}. {requirement} Ask the DB team to upgrade the database, or change GLPI_VERSION to a compatible GLPI 10.x version. Do not run deploy apply app until this is resolved."

emit("status", status)
emit("engine", engine)
emit("version", detected_version)
emit("minimum", minimum or "unknown")
emit("requirement", requirement)
emit("message", message)
PY
}

glpi_db_compatibility_value() {
  local report="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, "", $0); print; exit}' <<<"$report"
}

probe_managed_db_version_local() {
  local db_host="$1"
  local db_port="$2"
  local db_name="$3"
  local db_user="$4"
  local db_password="$5"
  local output

  if output="$(MYSQL_PWD="$db_password" mysql \
    --protocol=TCP \
    --host="$db_host" \
    --port="$db_port" \
    --user="$db_user" \
    --database="$db_name" \
    --batch \
    --skip-column-names \
    --connect-timeout=7 \
    --execute='SELECT VERSION(), @@version_comment;' 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi

  printf '%s\n' "$output"
  return 1
}

resolve_execution_mode_for_environment() {
  local environment="$1"
  local mode="${GLPI_EXECUTION_MODE:-}"

  if [[ -z "${mode// }" ]] && [[ -f "$(config_file_path "$environment")" ]]; then
    mode="$(read_product_config_value "$environment" "execution.mode" || true)"
  fi
  [[ -z "${mode// }" ]] && mode="local"
  case "$mode" in
    local|ssh) echo "$mode" ;;
    *) echo "invalid" ;;
  esac
}

resolve_host_role_for_environment() {
  local environment="$1"
  local role="${GLPI_HOST_ROLE:-}"

  if [[ -z "${role// }" ]] && [[ -f "$(config_file_path "$environment")" ]]; then
    role="$(read_product_config_value "$environment" "execution.host_role_default" || true)"
  fi
  [[ -z "${role// }" ]] && role="all"
  case "$role" in
    app|db|all) echo "$role" ;;
    *) echo "invalid" ;;
  esac
}

resolve_database_deployment_mode_for_environment() {
  local environment="$1"
  local mode=""

  if [[ -f "$(config_file_path "$environment")" ]]; then
    mode="$(read_product_config_value "$environment" "database.deployment_mode" || true)"
  fi
  [[ -z "${mode// }" ]] && mode="self_hosted"
  case "$mode" in
    self_hosted|managed) echo "$mode" ;;
    *) echo "invalid" ;;
  esac
}

resolve_security_mode_for_environment() {
  local environment="$1"
  local mode="${SECURITY_MODE:-}"

  if [[ -z "${mode// }" ]] && [[ -f "$(config_file_path "$environment")" ]]; then
    mode="$(read_product_config_value "$environment" "operations.security_mode_default" || true)"
  fi
  [[ -z "${mode// }" ]] && mode="secure"
  case "$mode" in
    secure|permissive) echo "$mode" ;;
    *) echo "invalid" ;;
  esac
}

run_preflight_checks() {
  local environment="${1:-unknown}"
  local command_domain="${2:-unknown}"
  local command_action="${3:-unknown}"
  local command_target="${4:-all}"
  shift 4 || true

  local -a mandatory_commands=()
  local -a optional_commands=("ssh")
  local mandatory_failures=0
  local optional_failures=0
  local disk_kb_available=0
  local disk_kb_required=1048576
  local runtime_base_dir="$SCRIPT_ROOT/../.runtime"
  local marker_file
  local items_file
  local topology_mode ssh_key_path ssh_user app_host db_host tls_mode glpi_version
  local db_port db_name db_user db_password
  local require_tls require_https require_promotion_gate
  local security_mode policy_obligation policy_status policy_block
  local execution_mode host_role db_deployment_mode require_privileged_checks
  local app_stack_expected glpi_major_version glpi_requires_bcmath php_version php_fpm_service
  local promotion_gate_path
  marker_file="$(bootstrap_marker_path)"
  items_file="$(preflight_items_file_path "$environment")"
  : >"$items_file"
  chmod 600 "$items_file"

  if (($# > 0)); then
    mandatory_commands=("$@")
  fi

  write_step "Running environment pre-flight checks for '$environment'"
  echo "Mandatory items must be fixed before continuing."
  echo "Optional items are recommended but do not block execution."
  require_privileged_checks="true"
  if [[ "$command_domain" == "deploy" && "$command_action" == "check" ]]; then
    require_privileged_checks="false"
  fi

  register_mandatory_failure() {
    mandatory_failures=$((mandatory_failures + 1))
    if [[ "${PREFLIGHT_FAIL_FAST:-true}" == "true" ]]; then
      finalize_precheck_reports "$environment" "$mandatory_failures" "$optional_failures"
      echo "Mandatory pre-flight check failed."
      echo "Stopping immediately because PREFLIGHT_FAIL_FAST=true."
      echo "Detailed report: $(preflight_report_latest_path "$environment")"
      echo "Readable summary: $(preflight_report_markdown_path "$environment")"
      exit 1
    fi
  }

  preflight_print_result "mandatory" "check" "bash available"
  if command -v bash >/dev/null 2>&1; then
    preflight_print_result "mandatory" "ok" "bash found"
    append_precheck_item "$environment" "bash" "local-tooling" "all" "mandatory" \
      "Script runtime requires bash." "command -v bash" "$(package_install_action "$(package_for_command bash)")" "true" "pass" "none"
  else
    preflight_print_result "mandatory" "fail" "bash not found"
    append_precheck_item "$environment" "bash" "local-tooling" "all" "mandatory" \
      "Script runtime requires bash." "command -v bash" "$(package_install_action "$(package_for_command bash)")" "true" "fail" "Install bash package."
    register_mandatory_failure
  fi

  if platform_supported; then
    append_precheck_item "$environment" "linux-platform-supported" "platform" "all" "mandatory" \
      "Supported platforms are Ubuntu 24.04 and Rocky/RHEL-like 9.x." "cat /etc/os-release" "manual host update" "true" "pass" "$(platform_human_name)"
  else
    append_precheck_item "$environment" "linux-platform-supported" "platform" "all" "mandatory" \
      "Supported platforms are Ubuntu 24.04 and Rocky/RHEL-like 9.x." "cat /etc/os-release" "manual host update" "true" "fail" "Use Ubuntu 24.04 or Rocky/RHEL-like 9.x before deployment."
    register_mandatory_failure
  fi

  if command -v df >/dev/null 2>&1; then
    disk_kb_available="$(df -Pk . | awk 'NR==2 {print $4}')"
    if [[ "${disk_kb_available:-0}" =~ ^[0-9]+$ ]] && ((disk_kb_available >= disk_kb_required)); then
      preflight_print_result "mandatory" "ok" "at least 1 GB of local free disk space is available"
      append_precheck_item "$environment" "local-free-disk" "local-host" "all" "mandatory" \
        "Runtime artifacts and logs need local disk." "df -Pk ." "manual cleanup" "true" "pass" "none"
    else
      preflight_print_result "mandatory" "fail" "less than 1 GB of local free disk space is available"
      append_precheck_item "$environment" "local-free-disk" "local-host" "all" "mandatory" \
        "Runtime artifacts and logs need local disk." "df -Pk ." "manual cleanup" "true" "fail" "Free at least 1 GB locally."
      register_mandatory_failure
    fi
  else
    preflight_print_result "optional" "warn" "df not found; free disk space was not validated"
    append_precheck_item "$environment" "local-free-disk" "local-host" "all" "optional" \
      "Disk validation is recommended for stability." "df -Pk ." "$(package_install_action coreutils)" "false" "warn" "Install coreutils for disk checks."
    optional_failures=$((optional_failures + 1))
  fi

  for cmd in "${mandatory_commands[@]}"; do
    local required_package
    required_package="$(package_for_command "$cmd")"
    if ! check_or_install_command "mandatory" "$cmd" "$required_package"; then
      append_precheck_item "$environment" "$cmd" "local-tooling" "all" "mandatory" \
        "Command is required by deployment workflow." "command -v $cmd" "$(package_install_action "$required_package")" "true" "fail" "Install package and rerun precheck."
      register_mandatory_failure
    else
      append_precheck_item "$environment" "$cmd" "local-tooling" "all" "mandatory" \
        "Command is required by deployment workflow." "command -v $cmd" "$(package_install_action "$required_package")" "true" "pass" "none"
    fi
  done

  if ! check_or_install_python_yaml_support "mandatory"; then
    append_precheck_item "$environment" "python3-yaml" "local-tooling" "all" "mandatory" \
      "Runtime rendering requires python3-yaml support." "python3 -c \"import yaml\"" "$(package_install_action "$(package_for_python_yaml)")" "true" "fail" "Install Python YAML package and rerun precheck."
    register_mandatory_failure
  else
    append_precheck_item "$environment" "python3-yaml" "local-tooling" "all" "mandatory" \
      "Runtime rendering requires python3-yaml support." "python3 -c \"import yaml\"" "$(package_install_action "$(package_for_python_yaml)")" "true" "pass" "none"
  fi

  local ansible_modules_status
  if ansible_modules_status="$(required_ansible_modules_available 2>&1)"; then
    preflight_print_result "mandatory" "ok" "required Ansible collections are available"
    append_precheck_item "$environment" "ansible-collections" "local-tooling" "all" "mandatory" \
      "Playbooks require Ansible collections declared in ansible/requirements.yml." "ansible-doc -t module community.mysql.mysql_db" "ansible-galaxy collection install -r ansible/requirements.yml" "true" "pass" "none"
  else
    preflight_print_result "mandatory" "fail" "required Ansible collections are missing: ${ansible_modules_status}"
    append_precheck_item "$environment" "ansible-collections" "local-tooling" "all" "mandatory" \
      "Playbooks require Ansible collections declared in ansible/requirements.yml." "ansible-doc -t module community.mysql.mysql_db" "ansible-galaxy collection install -r ansible/requirements.yml" "true" "fail" "Run ansible-galaxy collection install -r ansible/requirements.yml and rerun precheck."
    register_mandatory_failure
  fi

  for cmd in "${optional_commands[@]}"; do
    local optional_package
    optional_package="$(package_for_command "$cmd")"
    if ! check_or_install_command "optional" "$cmd" "$optional_package"; then
      preflight_print_result "optional" "warn" "command '$cmd' remains unavailable"
      append_precheck_item "$environment" "$cmd" "local-tooling" "all" "optional" \
        "Useful for connectivity diagnostics and remote checks." "command -v $cmd" "$(package_install_action "$optional_package")" "false" "warn" "Install optional package for diagnostics."
      optional_failures=$((optional_failures + 1))
    else
      append_precheck_item "$environment" "$cmd" "local-tooling" "all" "optional" \
        "Useful for connectivity diagnostics and remote checks." "command -v $cmd" "$(package_install_action "$optional_package")" "false" "pass" "none"
    fi
  done

  if [[ "$require_privileged_checks" != "true" ]]; then
    append_precheck_item "$environment" "sudo-ready" "permissions" "deploy check flow" "not-applicable" \
      "Deploy check performs validation only and does not require sudo/root capability." "sudo -v" "n/a" "false" "skip" "none"
  else
    if ! ensure_sudo_ready; then
      preflight_print_result "mandatory" "fail" "sudo/root capability is required"
      append_precheck_item "$environment" "sudo-ready" "permissions" "all" "mandatory" \
        "Package install and permission hardening need sudo/root." "sudo -v" "manual sudo policy update" "true" "fail" "Grant sudo or run as root."
      register_mandatory_failure
    else
      preflight_print_result "mandatory" "ok" "sudo/root capability validated"
      append_precheck_item "$environment" "sudo-ready" "permissions" "all" "mandatory" \
        "Package install and permission hardening need sudo/root." "sudo -v" "manual sudo policy update" "true" "pass" "none"
    fi
  fi

  if [[ "$require_privileged_checks" != "true" ]]; then
    append_precheck_item "$environment" "ops-group-membership" "permissions" "deploy check flow" "not-applicable" \
      "Deploy check flow does not require mutable privileged operations." "id -nG | grep glpiops" "n/a" "false" "skip" "none"
  else
    if ! ensure_group_exists_and_membership "$GLPI_OPS_GROUP"; then
      preflight_print_result "mandatory" "fail" "operator must belong to group '$GLPI_OPS_GROUP'"
      append_precheck_item "$environment" "ops-group-membership" "permissions" "all" "mandatory" \
        "Least-privilege operator model requires glpiops." "id -nG | grep glpiops" "groupadd/usermod" "true" "fail" "Add user to glpiops and relogin."
      register_mandatory_failure
    else
      preflight_print_result "mandatory" "ok" "operator belongs to group '$GLPI_OPS_GROUP'"
      append_precheck_item "$environment" "ops-group-membership" "permissions" "all" "mandatory" \
        "Least-privilege operator model requires glpiops." "id -nG | grep glpiops" "groupadd/usermod" "true" "pass" "none"
    fi
  fi

  if ! ensure_directory_mode "$runtime_base_dir" "700"; then
    preflight_print_result "mandatory" "fail" "runtime base directory permissions are not compliant"
    append_precheck_item "$environment" "runtime-base-permissions" "permissions" "all" "mandatory" \
      "Runtime artifacts include sensitive data and must stay restricted." "stat -c '%a' .runtime" "chmod 700 .runtime" "true" "fail" "Apply secure permissions on .runtime."
    register_mandatory_failure
  else
    preflight_print_result "mandatory" "ok" "runtime base directory permissions are compliant"
    append_precheck_item "$environment" "runtime-base-permissions" "permissions" "all" "mandatory" \
      "Runtime artifacts include sensitive data and must stay restricted." "stat -c '%a' .runtime" "chmod 700 .runtime" "true" "pass" "none"
  fi

  if [[ -f "$marker_file" ]]; then
    if ! ensure_mode "$marker_file" "600"; then
      preflight_print_result "mandatory" "fail" "bootstrap marker permissions are not compliant"
      append_precheck_item "$environment" "bootstrap-marker-permissions" "permissions" "all" "mandatory" \
        "Bootstrap marker must stay restricted to the operator context." "stat -c '%a' .runtime/bootstrap.completed" "chmod 600 .runtime/bootstrap.completed" "true" "fail" "Fix bootstrap marker mode to 600."
      register_mandatory_failure
    else
      preflight_print_result "mandatory" "ok" "bootstrap marker permissions are compliant"
      append_precheck_item "$environment" "bootstrap-marker-permissions" "permissions" "all" "mandatory" \
        "Bootstrap marker must stay restricted to the operator context." "stat -c '%a' .runtime/bootstrap.completed" "chmod 600 .runtime/bootstrap.completed" "true" "pass" "none"
    fi
  fi

  if [[ -f "$(config_file_path "$environment")" ]]; then
    topology_mode="$(read_product_config_value "$environment" "topology.mode" || true)"
    ssh_key_path="$(read_product_config_value "$environment" "network.ssh.private_key_path" || true)"
    ssh_user="$(read_product_config_value "$environment" "network.ssh.user" || true)"
    app_host="$(read_product_config_value "$environment" "topology.app.host" || true)"
    db_host="$(read_product_config_value "$environment" "topology.db.host" || true)"
    db_port="$(read_product_config_value "$environment" "DATABASE_PORT" || true)"
    db_name="$(read_product_config_value "$environment" "DATABASE_NAME" || true)"
    db_user="$(read_product_config_value "$environment" "DATABASE_USER" || true)"
    db_password="$(read_product_config_value "$environment" "DATABASE_PASSWORD" || true)"
    glpi_version="$(read_product_config_value "$environment" "glpi.version" || true)"
    tls_mode="$(read_product_config_value "$environment" "tls.mode" || true)"
    security_mode="$(resolve_security_mode_for_environment "$environment")"
    execution_mode="$(resolve_execution_mode_for_environment "$environment")"
    host_role="$(resolve_host_role_for_environment "$environment")"
    db_deployment_mode="$(resolve_database_deployment_mode_for_environment "$environment")"
    php_version="$(resolve_php_version_for_environment "$environment")"
    php_fpm_service="$(read_product_config_value "$environment" "php_fpm.service_name" || true)"
    [[ -z "${php_fpm_service// }" ]] && php_fpm_service="php${php_version}-fpm"
    [[ -z "${topology_mode// }" ]] && topology_mode="dual-server"
    [[ -z "${tls_mode// }" ]] && tls_mode="none"
    [[ -z "${db_port// }" ]] && db_port="3306"
    if [[ -z "${db_password// }" && -f "$(runtime_secret_path "$environment")" ]]; then
      db_password="$(read_yaml_top_level_value "$(runtime_secret_path "$environment")" "glpi_db_password" || true)"
    fi
    [[ -z "${db_deployment_mode// }" ]] && db_deployment_mode="self_hosted"
    promotion_gate_path="$SCRIPT_ROOT/../.runtime/promotion/staging-certified.yml"

    if [[ "$execution_mode" == "invalid" ]]; then
      append_precheck_item "$environment" "execution-mode-default" "execution-contract" "all" "mandatory" \
        "Execution mode must be local or ssh." "GLPI_EXECUTION_MODE env var or EXECUTION_MODE in config/<environment>.env" "set local or ssh" "true" "fail" "Fix EXECUTION_MODE in config or GLPI_EXECUTION_MODE."
      register_mandatory_failure
      execution_mode="local"
    else
      append_precheck_item "$environment" "execution-mode-default" "execution-contract" "all" "mandatory" \
        "Execution mode controls inventory rendering and connectivity checks." "GLPI_EXECUTION_MODE env var or EXECUTION_MODE in config/<environment>.env" "set local or ssh" "true" "pass" "mode=${execution_mode}"
    fi

    if [[ "$host_role" == "invalid" ]]; then
      append_precheck_item "$environment" "host-role-default" "execution-contract" "all" "mandatory" \
        "Host role must be app, db, or all." "GLPI_HOST_ROLE env var or EXECUTION_HOST_ROLE_DEFAULT in config/<environment>.env" "set app/db/all" "true" "fail" "Fix host role in config or GLPI_HOST_ROLE."
      register_mandatory_failure
      host_role="all"
    else
      append_precheck_item "$environment" "host-role-default" "execution-contract" "all" "mandatory" \
        "Host role controls allowed mutable actions in local mode." "GLPI_HOST_ROLE env var or EXECUTION_HOST_ROLE_DEFAULT in config/<environment>.env" "set app/db/all" "true" "pass" "role=${host_role}"
    fi

    if [[ "$db_deployment_mode" == "invalid" ]]; then
      append_precheck_item "$environment" "database-deployment-mode" "execution-contract" "all" "mandatory" \
        "Database deployment mode must be self_hosted or managed." "DATABASE_DEPLOYMENT_MODE in config/<environment>.env" "set self_hosted or managed" "true" "fail" "Fix DATABASE_DEPLOYMENT_MODE in config."
      register_mandatory_failure
      db_deployment_mode="self_hosted"
    else
      append_precheck_item "$environment" "database-deployment-mode" "execution-contract" "all" "mandatory" \
        "Database deployment mode controls DB-host orchestration behavior." "DATABASE_DEPLOYMENT_MODE in config/<environment>.env" "set self_hosted or managed" "true" "pass" "mode=${db_deployment_mode}"
    fi

    app_stack_expected="false"
    if [[ "$command_domain" == "deploy" ]]; then
      case "$command_target" in
        app|all)
          if [[ "$execution_mode" == "local" ]]; then
            if [[ "$host_role" == "app" || "$host_role" == "all" ]]; then
              app_stack_expected="true"
            fi
          fi
          ;;
      esac
    fi

    glpi_major_version="0"
    if [[ "$glpi_version" =~ ^([0-9]+)\. ]]; then
      glpi_major_version="${BASH_REMATCH[1]}"
    fi
    glpi_requires_bcmath="false"
    if (( glpi_major_version >= 11 )); then
      glpi_requires_bcmath="true"
    fi

    if [[ "$app_stack_expected" == "true" ]]; then
      local mysql_client_package
      mysql_client_package="$(package_for_command mysql)"
      if check_or_install_command "mandatory" "mysql" "$mysql_client_package"; then
        append_precheck_item "$environment" "mysql-client-on-app-host" "local-tooling" "deploy/apply app in local mode" "mandatory" \
          "App host needs a MySQL-compatible client for DB connectivity validation and diagnostics." "command -v mysql" "$(package_install_action "$mysql_client_package")" "true" "pass" "none"
      else
        append_precheck_item "$environment" "mysql-client-on-app-host" "local-tooling" "deploy/apply app in local mode" "mandatory" \
          "App host needs a MySQL-compatible client for DB connectivity validation and diagnostics." "command -v mysql" "$(package_install_action "$mysql_client_package")" "true" "fail" "Install a MySQL-compatible client package and rerun precheck."
        register_mandatory_failure
      fi
    else
      append_precheck_item "$environment" "mysql-client-on-app-host" "local-tooling" "non-app local target or ssh execution" "not-applicable" \
        "MySQL-compatible client on local host is required only for app-host local verification flow." "command -v mysql" "n/a" "false" "skip" "none"
    fi

    if [[ "$db_deployment_mode" == "managed" ]]; then
      if [[ "$app_stack_expected" != "true" ]]; then
        append_precheck_item "$environment" "managed-db-version-compatible" "database" "non-app local target or ssh execution" "not-applicable" \
          "Managed DB version compatibility is enforced before app deployment." "SELECT VERSION(), @@version_comment" "n/a" "false" "skip" "none"
      elif [[ -z "${db_password// }" ]]; then
        append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=managed" "conditional-mandatory" \
          "Managed DB version must be compatible with configured GLPI version before app mutation." "SELECT VERSION(), @@version_comment" "n/a" "true" "skip" "database password not available in check-only flow; deploy prepare/apply will block before app mutation."
      elif [[ -z "${db_host// }" || -z "${db_name// }" || -z "${db_user// }" ]]; then
        append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=managed" "mandatory" \
          "Managed DB version must be compatible with configured GLPI version before app mutation." "TOPOLOGY_DB_HOST + DATABASE_NAME + DATABASE_USER" "set managed DB connection keys" "true" "fail" "Set TOPOLOGY_DB_HOST, DATABASE_NAME and DATABASE_USER in config/<environment>.env."
        register_mandatory_failure
      elif ! command -v mysql >/dev/null 2>&1; then
        append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=managed" "mandatory" \
          "Managed DB version must be compatible with configured GLPI version before app mutation." "command -v mysql && SELECT VERSION()" "$(package_install_action "$(package_for_command mysql)")" "true" "fail" "Install a MySQL-compatible client and rerun precheck."
        register_mandatory_failure
      else
        local managed_db_version_output managed_db_compat_report managed_db_compat_status managed_db_compat_message
        if managed_db_version_output="$(probe_managed_db_version_local "$db_host" "$db_port" "$db_name" "$db_user" "$db_password")"; then
          managed_db_compat_report="$(glpi_db_compatibility_report "$glpi_version" "$managed_db_version_output")"
          managed_db_compat_status="$(glpi_db_compatibility_value "$managed_db_compat_report" "status")"
          managed_db_compat_message="$(glpi_db_compatibility_value "$managed_db_compat_report" "message")"
          if [[ "$managed_db_compat_status" == "pass" ]]; then
            append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=managed" "mandatory" \
              "Managed DB version must be compatible with configured GLPI version before app mutation." "SELECT VERSION(), @@version_comment" "n/a" "true" "pass" "$managed_db_compat_message"
          else
            append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=managed" "mandatory" \
              "Managed DB version must be compatible with configured GLPI version before app mutation." "SELECT VERSION(), @@version_comment" "n/a" "true" "fail" "$managed_db_compat_message"
            register_mandatory_failure
          fi
        else
          append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=managed" "mandatory" \
            "Managed DB version must be compatible with configured GLPI version before app mutation." "SELECT VERSION(), @@version_comment" "n/a" "true" "fail" "Unable to inspect managed DB version. Validate host, port, protocol, firewall, database name, user and password. A TCP ping alone is not sufficient."
          register_mandatory_failure
        fi
      fi
    else
      append_precheck_item "$environment" "managed-db-version-compatible" "database" "DATABASE_DEPLOYMENT_MODE=self_hosted" "not-applicable" \
        "Managed DB compatibility gate is not required before self-hosted DB provisioning." "n/a" "n/a" "false" "skip" "none"
    fi

    if [[ "$glpi_requires_bcmath" == "true" ]]; then
      if [[ "$app_stack_expected" == "true" ]]; then
        local bcmath_package
        bcmath_package="$(php_extension_package_for_platform "bcmath" "$php_version")"
        if check_or_install_php_extension "mandatory" "bcmath" "$php_version" "$php_fpm_service"; then
          append_precheck_item "$environment" "php-extension-bcmath" "php-runtime" "GLPI >= 11 on app-host local flow" "mandatory" \
            "GLPI 11 requires bcmath extension for QR code support." "php -m | grep -i '^bcmath$'" "$(package_install_action "$bcmath_package")" "true" "pass" "none"
        else
          append_precheck_item "$environment" "php-extension-bcmath" "php-runtime" "GLPI >= 11 on app-host local flow" "mandatory" \
            "GLPI 11 requires bcmath extension for QR code support." "php -m | grep -i '^bcmath$'" "$(package_install_action "$bcmath_package")" "true" "fail" "Install PHP bcmath package and rerun precheck."
          register_mandatory_failure
        fi
      else
        append_precheck_item "$environment" "php-extension-bcmath" "php-runtime" "non-app local target or ssh execution" "not-applicable" \
          "bcmath is enforced on the app host runtime; remote or db-host local checks skip local PHP verification." "php -m | grep -i '^bcmath$'" "n/a" "false" "skip" "none"
      fi
    fi

    if [[ "$security_mode" == "invalid" ]]; then
      append_precheck_item "$environment" "security-mode-default" "environment-policy" "all" "mandatory" \
        "The default security mode must be secure or permissive." "OPERATIONS_SECURITY_MODE_DEFAULT in config/<environment>.env" "set secure or permissive" "true" "fail" "Fix OPERATIONS_SECURITY_MODE_DEFAULT to secure|permissive."
      register_mandatory_failure
      security_mode="secure"
    else
      append_precheck_item "$environment" "security-mode-default" "environment-policy" "all" "mandatory" \
        "Execution mode controls policy block behavior." "SECURITY_MODE env var or config value" "set secure or permissive" "true" "pass" "mode=${security_mode}"
    fi

    policy_obligation="mandatory"
    policy_status="pass"
    policy_block="true"
    if [[ "$security_mode" == "permissive" ]]; then
      policy_obligation="conditional-mandatory"
      policy_status="warn"
      policy_block="false"
    fi

    require_tls="$(read_product_config_value "$environment" "security.require_tls" || true)"
    if [[ -z "${require_tls// }" ]]; then
      require_tls="$(read_product_config_value "$environment" "security.require_tls_in_production" || true)"
    fi
    require_tls="$(normalize_bool_value "$require_tls" "false")"

    require_https="$(read_product_config_value "$environment" "security.require_https" || true)"
    if [[ -z "${require_https// }" ]]; then
      require_https="$(read_product_config_value "$environment" "security.require_https_in_production" || true)"
    fi
    require_https="$(normalize_bool_value "$require_https" "false")"

    require_promotion_gate="$(read_product_config_value "$environment" "security.require_promotion_gate" || true)"
    require_promotion_gate="$(normalize_bool_value "$require_promotion_gate" "false")"

    if ensure_ssh_key_material_for_environment "$environment" "$topology_mode" "$execution_mode" "$ssh_key_path" "$ssh_user" "$app_host" "$db_host" "$db_deployment_mode"; then
      append_precheck_item "$environment" "ssh-key-policy" "security-artifact" "$topology_mode" "conditional-mandatory" \
        "Remote execution requires one SSH key pair per environment with private key mode 0600 and reachable managed targets when EXECUTION_MODE=ssh." "ssh -i <key> <user>@<host>" "chmod 600; distribute public key" "true" "pass" "none"
    else
      append_precheck_item "$environment" "ssh-key-policy" "security-artifact" "$topology_mode" "conditional-mandatory" \
        "Remote execution requires one SSH key pair per environment with private key mode 0600 and reachable managed targets when EXECUTION_MODE=ssh." "ssh -i <key> <user>@<host>" "chmod 600; distribute public key" "true" "fail" "Generate/distribute environment SSH key pair and validate connectivity."
      register_mandatory_failure
    fi

    if [[ "$execution_mode" == "local" ]]; then
      local role_status role_remediation role_message
      role_status="pass"
      role_message="Host role and command target are consistent."
      role_remediation="none"

      if [[ "$command_domain" == "deploy" && "$command_action" == "apply" ]]; then
        case "$command_target" in
          db)
            if [[ "$host_role" != "db" && "$host_role" != "all" ]]; then
              role_status="fail"
              role_message="Local mode requires GLPI_HOST_ROLE=db|all for deploy apply db."
              role_remediation="Set GLPI_HOST_ROLE=db on DB host, or GLPI_HOST_ROLE=all for single-host deployment."
            fi
            ;;
          app|monitoring|backup)
            if [[ "$host_role" != "app" && "$host_role" != "all" ]]; then
              role_status="fail"
              role_message="Local mode requires GLPI_HOST_ROLE=app|all for deploy apply ${command_target}."
              role_remediation="Set GLPI_HOST_ROLE=app on APP host, or GLPI_HOST_ROLE=all for single-host deployment."
            fi
            ;;
          all)
            if [[ "$topology_mode" == "dual-server" && "$host_role" != "all" ]]; then
              role_status="fail"
              role_message="Local mode dual-server does not allow deploy apply all with host role app/db."
              role_remediation="Run role-specific apply commands on each host, or use GLPI_HOST_ROLE=all only for single-host deployment."
            fi
            ;;
        esac
      fi

      append_precheck_item "$environment" "host-role-command-consistency" "execution-contract" "EXECUTION_MODE=local" "mandatory" \
        "Local execution enforces host role and mutable command consistency." "GLPI_HOST_ROLE + command target" "set host role and run command on correct host" "true" "$role_status" "$role_remediation"
      if [[ "$role_status" == "fail" ]]; then
        register_mandatory_failure
      fi
    else
      append_precheck_item "$environment" "host-role-command-consistency" "execution-contract" "EXECUTION_MODE=ssh" "not-applicable" \
        "Role-target consistency checks are enforced only for local mode." "n/a" "n/a" "false" "skip" "none"
    fi

    if [[ "$tls_mode" == "provided" ]]; then
      local provided_cert provided_key
      provided_cert="$(read_product_config_value "$environment" "tls.provided_local_cert_path" || true)"
      provided_key="$(read_product_config_value "$environment" "tls.provided_local_key_path" || true)"
      if [[ -n "${provided_cert// }" && -n "${provided_key// }" && -f "$(expand_home_path "$provided_cert")" && -f "$(expand_home_path "$provided_key")" ]]; then
        append_precheck_item "$environment" "tls-provided-local-files" "security-artifact" "TLS_MODE=provided" "conditional-mandatory" \
          "Provided TLS mode requires local certificate and key files." "test -f <cert> && test -f <key>" "set valid local paths in config" "true" "pass" "none"
      else
        append_precheck_item "$environment" "tls-provided-local-files" "security-artifact" "TLS_MODE=provided" "conditional-mandatory" \
          "Provided TLS mode requires local certificate and key files." "test -f <cert> && test -f <key>" "set valid local paths in config" "true" "fail" "Provide valid local cert/key paths for provided mode."
        register_mandatory_failure
      fi
    else
      append_precheck_item "$environment" "tls-provided-local-files" "security-artifact" "TLS_MODE!=provided" "not-applicable" \
        "Provided TLS paths are only required when provided mode is selected." "n/a" "n/a" "false" "skip" "none"
    fi

    if [[ "$require_tls" == "true" ]]; then
      if [[ "$tls_mode" == "provided" ]]; then
        append_precheck_item "$environment" "policy-require-tls" "environment-policy" "all" "$policy_obligation" \
          "Secure policy requires provided TLS mode." "TLS_MODE in config/<environment>.env" "set TLS_MODE=provided" "$policy_block" "pass" "none"
      else
        append_precheck_item "$environment" "policy-require-tls" "environment-policy" "all" "$policy_obligation" \
          "Secure policy requires provided TLS mode." "TLS_MODE in config/<environment>.env" "set TLS_MODE=provided" "$policy_block" "$policy_status" "Enable provided TLS mode or run in secure mode only after compliance."
        if [[ "$security_mode" == "secure" ]]; then
          register_mandatory_failure
        else
          optional_failures=$((optional_failures + 1))
        fi
      fi
    fi

    if [[ "$require_https" == "true" ]]; then
      if [[ "$tls_mode" != "none" ]]; then
        append_precheck_item "$environment" "policy-require-https" "environment-policy" "all" "$policy_obligation" \
          "Secure policy requires HTTPS/TLS enabled." "TLS_MODE in config/<environment>.env" "set TLS_MODE to self_signed or provided" "$policy_block" "pass" "none"
      else
        append_precheck_item "$environment" "policy-require-https" "environment-policy" "all" "$policy_obligation" \
          "Secure policy requires HTTPS/TLS enabled." "TLS_MODE in config/<environment>.env" "set TLS_MODE to self_signed or provided" "$policy_block" "$policy_status" "Enable TLS mode or accept risk in permissive mode."
        if [[ "$security_mode" == "secure" ]]; then
          register_mandatory_failure
        else
          optional_failures=$((optional_failures + 1))
        fi
      fi
    fi

    if [[ "$require_promotion_gate" == "true" ]]; then
      if [[ -f "$promotion_gate_path" ]]; then
        append_precheck_item "$environment" "policy-require-promotion-gate" "environment-policy" "all" "$policy_obligation" \
          "Secure policy may require a valid staging certification gate." "test -f .runtime/promotion/staging-certified.yml" "run staging certification or disable gate requirement" "$policy_block" "pass" "none"
      else
        append_precheck_item "$environment" "policy-require-promotion-gate" "environment-policy" "all" "$policy_obligation" \
          "Secure policy may require a valid staging certification gate." "test -f .runtime/promotion/staging-certified.yml" "run staging certification or disable gate requirement" "$policy_block" "$policy_status" "Generate promotion gate or accept risk in permissive mode."
        if [[ "$security_mode" == "secure" ]]; then
          register_mandatory_failure
        else
          optional_failures=$((optional_failures + 1))
        fi
      fi
    fi
  else
    local copy_cmd
    copy_cmd="cp config/.env.example config/${environment}.env"
    preflight_print_result "mandatory" "fail" "missing required environment file: config/${environment}.env"
    append_precheck_item "$environment" "product-config-file" "configuration" "all" "mandatory" \
      "Runtime and policy checks depend on public environment config." "test -f config/<environment>.env" "$copy_cmd" "true" "fail" "Create config/${environment}.env from config/.env.example and adjust values."
    register_mandatory_failure
  fi

  finalize_precheck_reports "$environment" "$mandatory_failures" "$optional_failures"

  if ((mandatory_failures > 0)); then
    echo "Mandatory pre-flight checks failed."
    echo "Fix the mandatory items before continuing."
    echo "If the user explicitly authorizes continuation, rerun with PREFLIGHT_FORCE_CONTINUE=true."
    echo "Detailed report: $(preflight_report_latest_path "$environment")"
    echo "Readable summary: $(preflight_report_markdown_path "$environment")"
    if [[ "$PREFLIGHT_FORCE_CONTINUE" != "true" ]]; then
      exit 1
    fi
    echo "Continuing only because PREFLIGHT_FORCE_CONTINUE=true was explicitly provided."
  fi

  if ((optional_failures > 0)); then
    echo "Optional pre-flight warnings were found. Review them before continuing mutable operations."
  fi
  echo "Detailed report: $(preflight_report_latest_path "$environment")"
  echo "Readable summary: $(preflight_report_markdown_path "$environment")"
}
