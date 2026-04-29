#!/usr/bin/env bash
set -euo pipefail

PREFLIGHT_FORCE_CONTINUE="${PREFLIGHT_FORCE_CONTINUE:-false}"
PREFLIGHT_AUTO_INSTALL="${PREFLIGHT_AUTO_INSTALL:-prompt}"

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
