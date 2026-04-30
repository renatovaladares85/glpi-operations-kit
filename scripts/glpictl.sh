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
  echo "Usage: ./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit> <action> [target] [scope]" >&2
  echo "Execution contract: GLPI_ENVIRONMENT, GLPI_EXECUTION_MODE=local|ssh, GLPI_HOST_ROLE=app|db|all, SECURITY_MODE=secure|permissive" >&2
  exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Unsupported environment name: $ENVIRONMENT (allowed: letters, numbers, '.', '-', '_')." >&2
  exit 1
fi
export GLPI_ENVIRONMENT="$ENVIRONMENT"

RUNTIME_DIR="$(runtime_env_dir "$ENVIRONMENT")"
INVENTORY_RUNTIME_PATH="$(runtime_inventory_path "$ENVIRONMENT")"
PUBLIC_RUNTIME_PATH="$(runtime_public_path "$ENVIRONMENT")"
OVERRIDE_RUNTIME_PATH="$(runtime_override_path "$ENVIRONMENT")"
SECRET_PATH="$(runtime_secret_path "$ENVIRONMENT")"
CONFIG_PATH="$(config_file_path "$ENVIRONMENT")"
PROMOTION_GATE_PATH="$SCRIPT_ROOT/../.runtime/promotion/staging-certified.yml"
DEPLOY_SEQUENCE_PATH="$(runtime_state_dir "$ENVIRONMENT")/deploy-sequence.yml"
OPERATION_ID="glpictl-$(date +%Y%m%d-%H%M%S)-${DOMAIN}-${ACTION}-${TARGET}"
OPERATION_STATUS="completed"

print_post_execution_checks() {
  echo "Validation commands (run on target host):"
  if [[ "$DOMAIN" == "deploy" && "$ACTION" == "apply" ]]; then
    case "$TARGET" in
      db|all)
        echo "  - sudo systemctl status mariadb --no-pager"
        echo "  - sudo systemctl is-active mariadb"
        echo "  - mysql -h <db-host> -u <glpi-db-user> -p -e \"SELECT 1;\""
        ;;
    esac
    case "$TARGET" in
      app|all)
        echo "  - sudo systemctl status nginx --no-pager"
        echo "  - sudo systemctl status php8.3-fpm --no-pager"
        echo "  - sudo systemctl is-active nginx php8.3-fpm"
        echo "  - curl -I http://<app-host>/"
        ;;
    esac
    case "$TARGET" in
      monitoring|all)
        echo "  - sudo systemctl status prometheus-node-exporter --no-pager || true"
        echo "  - sudo systemctl status mysqld-exporter --no-pager || true"
        ;;
    esac
  fi
  if [[ "$DOMAIN" == "deploy" && "$ACTION" == "post-check" ]]; then
    echo "  - cat .runtime/${ENVIRONMENT}/evidence/precheck-report-latest.md"
    echo "  - ls -l .runtime/${ENVIRONMENT}/logs/"
  fi
  if [[ "$DOMAIN" == "tls" ]]; then
    echo "  - sudo nginx -t"
    echo "  - sudo systemctl reload nginx"
    echo "  - openssl s_client -connect <app-host>:443 -servername <app-host> </dev/null 2>/dev/null | openssl x509 -noout -dates"
  fi
}

finalize_glpictl_operation() {
  local exit_code="${1:-0}"
  local remediation_hint="none"
  if [[ "$exit_code" -ne 0 ]]; then
    OPERATION_STATUS="failed"
    remediation_hint="Review console output and .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log"
  fi
  complete_operation_log "$ENVIRONMENT" "$OPERATION_ID" "$OPERATION_STATUS" "${DOMAIN}/${ACTION}/${TARGET}" "$remediation_hint"
  if [[ "$exit_code" -eq 0 ]]; then
    echo "FINAL STATUS: SUCCESS"
    echo "Execution log: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log"
    echo "Execution summary: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.summary.yml"
    print_post_execution_checks
  else
    echo "FINAL STATUS: FAILED" >&2
    echo "Execution log: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.log" >&2
    echo "Execution summary: .runtime/${ENVIRONMENT}/logs/${OPERATION_ID}.summary.yml" >&2
  fi
}

SECURITY_MODE_EFFECTIVE=""
REQUIRE_TLS="false"
REQUIRE_HTTPS="false"
REQUIRE_SSO="false"
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

normalize_bool() {
  local value="$1"
  local default_value="${2:-false}"
  case "$value" in
    true|false) echo "$value" ;;
    *) echo "$default_value" ;;
  esac
}

yaml_escape() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
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

resolve_policy_contract() {
  REQUIRE_TLS="$(read_policy_flag "security.require_tls" "security.require_tls_in_production" "false")"
  REQUIRE_HTTPS="$(read_policy_flag "security.require_https" "security.require_https_in_production" "false")"
  REQUIRE_SSO="$(read_policy_flag "security.require_sso" "security.require_sso_in_production" "false")"
  REQUIRE_PROMOTION_GATE="$(read_policy_flag "security.require_promotion_gate" "" "false")"
  REQUIRE_ORDERED_EXECUTION="$(read_policy_flag "security.require_ordered_execution" "" "true")"
}

is_mutating_operation() {
  case "$DOMAIN/$ACTION" in
    deploy/apply|deploy/post-check|tls/*|promote/*|ops/*) return 0 ;;
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
  if [[ "$SECURITY_MODE_EFFECTIVE" == "secure" ]]; then
    echo "Execution blocked by security policy [$policy_id]: $message" >&2
    echo "Remediation: $remediation" >&2
    exit 1
  fi
  ensure_permissive_justification
  echo "WARNING: permissive mode accepted policy risk [$policy_id]: $message" >&2
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
    app) require_deploy_flag "db_applied" "Run apply db before apply app." ;;
    monitoring|backup)
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
  local sso_enabled

  sso_enabled="$(read_product_config_value "$ENVIRONMENT" "security.sso_enabled" || true)"
  [[ -z "${sso_enabled// }" ]] && sso_enabled="false"

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
  if [[ "$REQUIRE_SSO" == "true" && "$sso_enabled" != "true" ]]; then
    policy_violation "require-sso" "Policy requires SECURITY_SSO_ENABLED=true in config/$ENVIRONMENT.env." "Enable SECURITY_SSO_ENABLED in environment config."
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

run_deploy() {
  local mode="$1"
  local target="$2"
  local post_check_tags="app,db"

  enforce_local_target_consistency "deploy" "$mode" "$target"

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
    write_step "Validating rendered Ansible inventory"
    ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list >/dev/null
    mark_apply_sequence "$mode" "$target"
    echo "Check completed successfully."
    return 0
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
      invoke_ansible "$ENVIRONMENT" "$tags" "${extra_var_files[@]}"
      mark_apply_sequence "$mode" "$target"
      ;;
    post-check)
      if [[ "$REQUIRE_ORDERED_EXECUTION" == "true" ]]; then
        require_deploy_flag "db_applied" "Run apply db before post-check."
        require_deploy_flag "app_applied" "Run apply app before post-check."
      fi
      case "$target" in
        app|db) post_check_tags="$target" ;;
        all)
          if [[ "$EXECUTION_MODE_EFFECTIVE" == "local" && "$TOPOLOGY_MODE_EFFECTIVE" == "dual-server" ]]; then
            if [[ "$HOST_ROLE_EFFECTIVE" == "app" ]]; then
              post_check_tags="app"
            elif [[ "$HOST_ROLE_EFFECTIVE" == "db" ]]; then
              post_check_tags="db"
            fi
          fi
          ;;
        *)
          echo "Unsupported post-check target: $target (expected app|db|all)" >&2
          exit 1
          ;;
      esac
      invoke_ansible "$ENVIRONMENT" "$post_check_tags" "$PUBLIC_RUNTIME_PATH" "$OVERRIDE_RUNTIME_PATH" "$SECRET_PATH"
      mark_apply_sequence "$mode" "$target"
      ;;
    *) echo "Unsupported deploy action: $mode (expected check|apply|post-check)" >&2; exit 1 ;;
  esac
}

run_certify() {
  if [[ "$ENVIRONMENT" != "staging" ]]; then
    echo "Certification is only supported for staging." >&2
    exit 1
  fi
  bash "$SCRIPT_ROOT/certify-staging.sh"
}

run_tls() {
  local tls_action="$ACTION"
  local domain local_cert_path local_key_path tls_mode use_tls
  ensure_runtime_inputs_if_missing
  resolve_policy_contract
  domain="$(awk -F'"' '/glpi_domain:/ {print $2}' "$PUBLIC_RUNTIME_PATH" | head -n1)"
  local_cert_path=""
  local_key_path=""
  tls_mode="none"
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
      local_cert_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" || true)"
      [[ -z "${local_cert_path// }" ]] && local_cert_path="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_provided_local_cert_path" || true)"
      local_key_path="$(read_yaml_top_level_value "$OVERRIDE_RUNTIME_PATH" "glpi_tls_provided_local_key_path" || true)"
      [[ -z "${local_key_path// }" ]] && local_key_path="$(read_yaml_top_level_value "$PUBLIC_RUNTIME_PATH" "glpi_tls_provided_local_key_path" || true)"
      ;;
    *)
      echo "Unsupported TLS action: $tls_action (expected disable|self-signed|install-provided|reload)" >&2
      exit 1
      ;;
  esac
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
  echo "TLS action '$tls_action' completed."
}

run_ops() {
  resolve_policy_contract
  enforce_security_policy_contract
  if [[ "$ACTION" == "users" ]]; then
    local users_action="$TARGET"
    local users_scope="${SCOPE:-os}"
    bash "$SCRIPT_ROOT/ops-maintenance.sh" users "$ENVIRONMENT" "$users_action" "$users_scope"
    return
  fi
  if [[ "$ACTION" == "cert" ]]; then
    bash "$SCRIPT_ROOT/ops-maintenance.sh" cert "$ENVIRONMENT" "$TARGET"
    return
  fi
  if [[ "$ACTION" == "audit" ]]; then
    bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
    return
  fi
  if [[ "$ACTION" == "resume" ]]; then
    bash "$SCRIPT_ROOT/ops-maintenance.sh" resume "$ENVIRONMENT"
    return
  fi
  echo "Unsupported ops action: $ACTION (expected users|cert|audit|resume)" >&2
  exit 1
}

run_audit() {
  bash "$SCRIPT_ROOT/ops-maintenance.sh" audit "$ENVIRONMENT" check
}

run_promote() {
  resolve_policy_contract
  enforce_promotion_gate_policy_if_required
  run_deploy apply "$TARGET"
}

resolve_security_mode
resolve_execution_contract
ensure_runtime_foundation "$ENVIRONMENT"
begin_operation_log "$ENVIRONMENT" "$OPERATION_ID" "$0 $*"
trap 'finalize_glpictl_operation "$?"' EXIT
ensure_bootstrap_baseline "$SCRIPT_ROOT"
run_preflight_checks "$ENVIRONMENT" "$DOMAIN" "$ACTION" "$TARGET" bash git python3 ansible-playbook ansible-inventory

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
  audit) run_audit ;;
  *)
    echo "Unsupported domain: $DOMAIN (expected deploy|certify|promote|tls|ops|audit)" >&2
    exit 1
    ;;
esac

if is_mutating_operation && [[ "$SECURITY_MODE_EFFECTIVE" == "permissive" ]]; then
  persist_permissive_evidence
fi
