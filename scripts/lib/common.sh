#!/usr/bin/env bash
set -euo pipefail

PREFLIGHT_FORCE_CONTINUE="${PREFLIGHT_FORCE_CONTINUE:-false}"

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

invoke_ansible() {
  local environment="$1"
  local tags="$2"
  shift 2

  assert_command "ansible-playbook"
  local inventory="$SCRIPT_ROOT/../ansible/inventories/$environment/hosts.yml"
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
    if command -v "$cmd" >/dev/null 2>&1; then
      preflight_print_result "mandatory" "ok" "command '$cmd' found"
    else
      preflight_print_result "mandatory" "fail" "command '$cmd' not found"
      mandatory_failures=$((mandatory_failures + 1))
    fi
  done

  for cmd in "${optional_commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      preflight_print_result "optional" "ok" "command '$cmd' found"
    else
      preflight_print_result "optional" "warn" "command '$cmd' not found"
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
