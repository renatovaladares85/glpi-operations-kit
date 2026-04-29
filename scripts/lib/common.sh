#!/usr/bin/env bash
set -euo pipefail

PREFLIGHT_FORCE_CONTINUE="${PREFLIGHT_FORCE_CONTINUE:-false}"
PREFLIGHT_AUTO_INSTALL="${PREFLIGHT_AUTO_INSTALL:-prompt}"
GLPI_OPS_GROUP="${GLPI_OPS_GROUP:-glpiops}"
CERT_RENEWAL_WARN_DAYS="${CERT_RENEWAL_WARN_DAYS:-30}"

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

current_uid() {
  id -u
}

is_root_user() {
  [[ "$(current_uid)" -eq 0 ]]
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
    read -r answer
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
  local mode
  mode="$(file_mode_octal "$path")"
  if [[ "$mode" == "$expected" ]]; then
    return 0
  fi
  if offer_fix_then_execute "Path '$path' has mode '${mode:-unknown}', expected '$expected'." "chmod $expected '$path'"; then
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
  current_user="$(id -un)"

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
  return 1
}

bootstrap_marker_path() {
  echo "$SCRIPT_ROOT/../.runtime/bootstrap.completed"
}

write_bootstrap_marker() {
  local marker
  marker="$(bootstrap_marker_path)"
  ensure_directory "$SCRIPT_ROOT/../.runtime"
  printf "bootstrap_completed_at=%s\nbootstrap_completed_by=%s\n" "$(date -u +%FT%TZ)" "$(id -un)" >"$marker"
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

ensure_runtime_foundation() {
  local environment="$1"
  ensure_directory_mode "$(runtime_environment_root "$environment")" "700"
  ensure_directory_mode "$(runtime_logs_dir "$environment")" "700"
  ensure_directory_mode "$(runtime_state_dir "$environment")" "700"
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
  local log_path
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

  exec > >(tee -a "$log_path") 2>&1
  echo "Operation log: $log_path"
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

  while true; do
    echo "$prompt"
    echo "  Required because: $reason"
    echo "  Will be written to: $target_path"
    if [[ "$secret" == "true" ]]; then
      read -r -s value
      printf '\n'
    else
      read -r value
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
  local inventory="${ANSIBLE_RUNTIME_INVENTORY:-$SCRIPT_ROOT/../ansible/inventories/$environment/hosts.yml}"
  local playbook="$SCRIPT_ROOT/../ansible/site.yml"
  local args=("-i" "$inventory" "$playbook")

  if [[ -n "$tags" ]]; then
    args+=("--tags" "$tags")
  fi

  for file in "$@"; do
    args+=("--extra-vars" "@$file")
  done

  ansible-playbook "${args[@]}"
}

preflight_print_result() {
  local level="$1"
  local status="$2"
  local message="$3"
  printf '[%s] [%s] %s\n' "$level" "$status" "$message"
}

package_for_command() {
  local command_name="$1"
  case "$command_name" in
    ansible-playbook|ansible-inventory) echo "ansible" ;;
    git) echo "git" ;;
    ssh) echo "openssh-client" ;;
    bash) echo "bash" ;;
    *) echo "" ;;
  esac
}

install_command_ubuntu() {
  local command_name="$1"
  local package_name="$2"
  local install_cmd=""

  if command -v sudo >/dev/null 2>&1; then
    install_cmd="sudo apt-get update && sudo apt-get install -y ${package_name}"
  else
    install_cmd="apt-get update && apt-get install -y ${package_name}"
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
    while true; do
      echo "Command '${command_name}' is missing (${level})."
      echo "Install now on this Ubuntu host using package '${package_name}'? [y/n]"
      read -r answer
      case "$answer" in
        y|Y|yes|YES) answer="y"; break ;;
        n|N|no|NO) answer="n"; break ;;
        *) echo "Please answer 'y' or 'n'." ;;
      esac
    done
  fi

  if [[ "$answer" != "y" ]]; then
    return 1
  fi

  if install_command_ubuntu "$command_name" "$package_name"; then
    if command -v "$command_name" >/dev/null 2>&1; then
      preflight_print_result "$level" "ok" "command '$command_name' installed successfully"
      return 0
    fi
  fi

  echo "Automatic installation failed for '${command_name}'." >&2
  echo "Manual remediation (Ubuntu):" >&2
  if command -v sudo >/dev/null 2>&1; then
    echo "  sudo apt-get update && sudo apt-get install -y ${package_name}" >&2
  else
    echo "  apt-get update && apt-get install -y ${package_name}" >&2
  fi
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

run_preflight_checks() {
  local environment="${1:-unknown}"
  shift || true

  local -a mandatory_commands=()
  local -a optional_commands=("ssh")
  local mandatory_failures=0
  local optional_failures=0
  local disk_kb_available=0
  local disk_kb_required=1048576
  local runtime_base_dir="$SCRIPT_ROOT/../.runtime"
  local marker_file
  marker_file="$(bootstrap_marker_path)"

  if (($# > 0)); then
    mandatory_commands=("$@")
  fi

  write_step "Running environment pre-flight checks for '$environment'"
  echo "Mandatory items must be fixed before continuing."
  echo "Optional items are recommended but do not block execution."

  preflight_print_result "mandatory" "check" "bash available"
  if command -v bash >/dev/null 2>&1; then
    preflight_print_result "mandatory" "ok" "bash found"
  else
    preflight_print_result "mandatory" "fail" "bash not found"
    mandatory_failures=$((mandatory_failures + 1))
  fi

  if command -v df >/dev/null 2>&1; then
    disk_kb_available="$(df -Pk . | awk 'NR==2 {print $4}')"
    if [[ "${disk_kb_available:-0}" =~ ^[0-9]+$ ]] && ((disk_kb_available >= disk_kb_required)); then
      preflight_print_result "mandatory" "ok" "at least 1 GB of local free disk space is available"
    else
      preflight_print_result "mandatory" "fail" "less than 1 GB of local free disk space is available"
      mandatory_failures=$((mandatory_failures + 1))
    fi
  else
    preflight_print_result "optional" "warn" "df not found; free disk space was not validated"
    optional_failures=$((optional_failures + 1))
  fi

  for cmd in "${mandatory_commands[@]}"; do
    if ! check_or_install_command "mandatory" "$cmd" "$(package_for_command "$cmd")"; then
      mandatory_failures=$((mandatory_failures + 1))
    fi
  done

  for cmd in "${optional_commands[@]}"; do
    if ! check_or_install_command "optional" "$cmd" "$(package_for_command "$cmd")"; then
      preflight_print_result "optional" "warn" "command '$cmd' remains unavailable"
      optional_failures=$((optional_failures + 1))
    fi
  done

  if ! ensure_sudo_ready; then
    preflight_print_result "mandatory" "fail" "sudo/root capability is required"
    mandatory_failures=$((mandatory_failures + 1))
  else
    preflight_print_result "mandatory" "ok" "sudo/root capability validated"
  fi

  if ! ensure_group_exists_and_membership "$GLPI_OPS_GROUP"; then
    preflight_print_result "mandatory" "fail" "operator must belong to group '$GLPI_OPS_GROUP'"
    mandatory_failures=$((mandatory_failures + 1))
  else
    preflight_print_result "mandatory" "ok" "operator belongs to group '$GLPI_OPS_GROUP'"
  fi

  if ! ensure_directory_mode "$runtime_base_dir" "700"; then
    preflight_print_result "mandatory" "fail" "runtime base directory permissions are not compliant"
    mandatory_failures=$((mandatory_failures + 1))
  else
    preflight_print_result "mandatory" "ok" "runtime base directory permissions are compliant"
  fi

  if [[ -f "$marker_file" ]]; then
    if ! ensure_mode "$marker_file" "600"; then
      preflight_print_result "mandatory" "fail" "bootstrap marker permissions are not compliant"
      mandatory_failures=$((mandatory_failures + 1))
    else
      preflight_print_result "mandatory" "ok" "bootstrap marker permissions are compliant"
    fi
  fi

  if ((mandatory_failures > 0)); then
    echo "Mandatory pre-flight checks failed."
    echo "Fix the mandatory items before continuing."
    echo "If the user explicitly authorizes continuation, rerun with PREFLIGHT_FORCE_CONTINUE=true."
    if [[ "$PREFLIGHT_FORCE_CONTINUE" != "true" ]]; then
      exit 1
    fi
    echo "Continuing only because PREFLIGHT_FORCE_CONTINUE=true was explicitly provided."
  fi

  if ((optional_failures > 0)); then
    echo "Optional pre-flight warnings were found. Review them before production use."
  fi
}
