#!/usr/bin/env bash
set -euo pipefail

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
