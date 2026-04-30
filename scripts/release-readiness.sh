#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_ROOT/lib/common.sh"

ENVIRONMENT="${1:-staging}"
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Usage: bash scripts/release-readiness.sh <environment>" >&2
  exit 1
fi

RUNTIME_DIR="$(runtime_env_dir "$ENVIRONMENT")"
EVIDENCE_DIR="$RUNTIME_DIR/evidence"
CONFIG_PATH="$(config_file_path "$ENVIRONMENT")"
INVENTORY_RUNTIME_PATH="$(runtime_inventory_path "$ENVIRONMENT")"
PUBLIC_RUNTIME_PATH="$(runtime_public_path "$ENVIRONMENT")"
OVERRIDE_RUNTIME_PATH="$(runtime_override_path "$ENVIRONMENT")"
SECRET_PATH="$(runtime_secret_path "$ENVIRONMENT")"
PROMOTION_GATE_PATH="$SCRIPT_ROOT/../.runtime/promotion/staging-certified.yml"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_MD="$EVIDENCE_DIR/readiness-report.md"
REPORT_JSON="$EVIDENCE_DIR/readiness-report.json"
ARTIFACT_DIR="$EVIDENCE_DIR/readiness-$TIMESTAMP"
RESULTS_FILE="$ARTIFACT_DIR/results.tsv"

critical_failures=0
warning_failures=0
total_checks=0

ensure_directory "$RUNTIME_DIR"
ensure_directory "$EVIDENCE_DIR"
ensure_directory "$ARTIFACT_DIR"
chmod 700 "$RUNTIME_DIR" "$EVIDENCE_DIR" "$ARTIFACT_DIR" >/dev/null 2>&1 || true
: >"$RESULTS_FILE"
chmod 600 "$RESULTS_FILE"

record_check() {
  local level="$1"
  local id="$2"
  local description="$3"
  local status="$4"
  local artifact="$5"
  printf '%s\t%s\t%s\t%s\t%s\n' "$level" "$id" "$description" "$status" "$artifact" >>"$RESULTS_FILE"
}

run_check() {
  local level="$1"
  local id="$2"
  local description="$3"
  local output_file="$4"
  shift 4

  total_checks=$((total_checks + 1))
  write_step "$id - $description"
  local rc=0
  set +e
  ("$@") >"$output_file" 2>&1
  rc=$?
  set -e
  local status="pass"
  if [[ "$rc" -ne 0 ]]; then
    status="fail"
    if [[ "$level" == "critical" ]]; then
      critical_failures=$((critical_failures + 1))
    else
      warning_failures=$((warning_failures + 1))
    fi
  fi
  echo "[$level] $id: $status"
  record_check "$level" "$id" "$description" "$status" "$output_file"
}

check_secret_keys() {
  require_runtime_file "$SECRET_PATH" "runtime secret file"
  local keys=(
    "glpi_db_password"
    "glpi_db_root_password"
    "mysqld_exporter_password"
  )
  local key value
  for key in "${keys[@]}"; do
    value="$(read_yaml_top_level_value "$SECRET_PATH" "$key" || true)"
    if [[ -z "${value// }" ]]; then
      echo "Missing required secret key: $key" >&2
      return 1
    fi
  done
  echo "All required secret keys are present."
}

check_docs_navigation() {
  grep -Fq "(docs/manual/README.md)" "$SCRIPT_ROOT/../README.md"
  grep -Fq "(en/user-manual.md)" "$SCRIPT_ROOT/../docs/manual/README.md"
  grep -Fq "(pt-br/user-manual.md)" "$SCRIPT_ROOT/../docs/manual/README.md"
  grep -Fq "(command-reference.md)" "$SCRIPT_ROOT/../docs/manual/en/appendices/index.md"
  grep -Fq "(command-reference.md)" "$SCRIPT_ROOT/../docs/manual/pt-br/appendices/index.md"
  grep -Fq "(../../product/configuration-reference.md)" "$SCRIPT_ROOT/../docs/manual/en/user-manual.md"
  grep -Fq "(../../product/configuration-reference.md)" "$SCRIPT_ROOT/../docs/manual/pt-br/user-manual.md"
}

check_runtime_precedence_docs() {
  grep -Fq "variable precedence is explicit" "$SCRIPT_ROOT/../docs/manual/en/appendices/runtime-input-reference.md"
  grep -Fq "1. \`public.runtime.yml\`" "$SCRIPT_ROOT/../docs/manual/en/appendices/runtime-input-reference.md"
  grep -Fq "2. \`overrides.runtime.yml\`" "$SCRIPT_ROOT/../docs/manual/en/appendices/runtime-input-reference.md"
  grep -Fq "3. \`secrets.yml\`" "$SCRIPT_ROOT/../docs/manual/en/appendices/runtime-input-reference.md"
  grep -Fq "Runtime values are merged in this order" "$SCRIPT_ROOT/../docs/product/configuration-reference.md"
}

check_render_public_runtime() {
  render_product_config "$ENVIRONMENT" public-runtime >"$PUBLIC_RUNTIME_PATH"
  chmod 600 "$PUBLIC_RUNTIME_PATH"
}

check_render_runtime_inventory() {
  render_product_config "$ENVIRONMENT" inventory >"$INVENTORY_RUNTIME_PATH"
  chmod 600 "$INVENTORY_RUNTIME_PATH"
}

check_runtime_override_file() {
  if [[ ! -f "$OVERRIDE_RUNTIME_PATH" ]]; then
    cat >"$OVERRIDE_RUNTIME_PATH" <<'EOF'
---
EOF
  fi
  chmod 600 "$OVERRIDE_RUNTIME_PATH" >/dev/null 2>&1 || true
  require_runtime_file "$OVERRIDE_RUNTIME_PATH" "runtime override file"
}

check_staging_certification_artifacts() {
  require_runtime_file "$PROMOTION_GATE_PATH" "staging promotion gate file"
  grep -Fq "status: 'approved'" "$PROMOTION_GATE_PATH"
  local report_path
  report_path="$(awk -F"'" '/^report_path:/ {print $2; exit}' "$PROMOTION_GATE_PATH")"
  if [[ -z "${report_path// }" || ! -f "$report_path" ]]; then
    echo "Referenced certification report not found: ${report_path:-missing}" >&2
    return 1
  fi
}

check_production_policy_contract() {
  local tls_mode sso_enabled require_tls require_https require_sso
  tls_mode="$(read_product_config_value "$ENVIRONMENT" "tls.mode" || true)"
  sso_enabled="$(read_product_config_value "$ENVIRONMENT" "security.sso_enabled" || true)"
  require_tls="$(read_product_config_value "$ENVIRONMENT" "security.require_tls" || true)"
  [[ -z "${require_tls// }" ]] && require_tls="$(read_product_config_value "$ENVIRONMENT" "security.require_tls_in_production" || true)"
  [[ -z "${require_tls// }" ]] && require_tls="false"
  require_https="$(read_product_config_value "$ENVIRONMENT" "security.require_https" || true)"
  [[ -z "${require_https// }" ]] && require_https="$(read_product_config_value "$ENVIRONMENT" "security.require_https_in_production" || true)"
  [[ -z "${require_https// }" ]] && require_https="false"
  require_sso="$(read_product_config_value "$ENVIRONMENT" "security.require_sso" || true)"
  [[ -z "${require_sso// }" ]] && require_sso="$(read_product_config_value "$ENVIRONMENT" "security.require_sso_in_production" || true)"
  [[ -z "${require_sso// }" ]] && require_sso="false"

  if [[ "$require_tls" == "true" && "$tls_mode" != "provided" ]]; then
    echo "Policy violation: TLS_MODE must be provided when SECURITY_REQUIRE_TLS=true." >&2
    return 1
  fi
  if [[ "$require_https" == "true" && "$tls_mode" == "none" ]]; then
    echo "Policy violation: TLS_MODE cannot be none when SECURITY_REQUIRE_HTTPS=true." >&2
    return 1
  fi
  if [[ "$require_sso" == "true" && "$sso_enabled" != "true" ]]; then
    echo "Policy violation: SECURITY_SSO_ENABLED must be true when SECURITY_REQUIRE_SSO=true." >&2
    return 1
  fi
}

write_report_markdown() {
  local overall_status="PASS"
  if ((critical_failures > 0)); then
    overall_status="FAIL"
  fi
  {
    echo "# Release Readiness Report"
    echo
    echo "- Environment: \`$ENVIRONMENT\`"
    echo "- Generated at (UTC): \`$(date -u +%FT%TZ)\`"
    echo "- Overall status: \`$overall_status\`"
    echo "- Total checks: \`$total_checks\`"
    echo "- Critical failures: \`$critical_failures\`"
    echo "- Warning failures: \`$warning_failures\`"
    echo
    echo "## Check Results"
    echo
    echo "| Level | Check | Description | Status | Artifact |"
    echo "|---|---|---|---|---|"
    while IFS=$'\t' read -r level id description status artifact; do
      echo "| $level | $id | $description | $status | \`$artifact\` |"
    done <"$RESULTS_FILE"
    echo
    echo "## Scope Notes"
    echo
    echo "- This gate validates script integrity, config rendering, inventory/syntax checks, documentation linkage, and secret presence."
    echo "- Real staging E2E execution remains mandatory through the operational flow and certification evidence."
    echo "- Production changes are intentionally excluded in this phase."
  } >"$REPORT_MD"
  chmod 600 "$REPORT_MD"
}

write_report_json() {
  python3 - "$RESULTS_FILE" "$REPORT_JSON" "$ENVIRONMENT" "$total_checks" "$critical_failures" "$warning_failures" <<'PY'
import json
import sys
from datetime import datetime, timezone

results_file = sys.argv[1]
output_file = sys.argv[2]
environment = sys.argv[3]
total_checks = int(sys.argv[4])
critical_failures = int(sys.argv[5])
warning_failures = int(sys.argv[6])

checks = []
with open(results_file, "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        level, check_id, description, status, artifact = line.split("\t")
        checks.append(
            {
                "level": level,
                "check_id": check_id,
                "description": description,
                "status": status,
                "artifact": artifact,
            }
        )

overall = "pass" if critical_failures == 0 else "fail"
payload = {
    "environment": environment,
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "overall_status": overall,
    "total_checks": total_checks,
    "critical_failures": critical_failures,
    "warning_failures": warning_failures,
    "checks": checks,
}

with open(output_file, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
PY
  chmod 600 "$REPORT_JSON"
}

run_check critical script-syntax "Validate bash syntax for all scripts." "$ARTIFACT_DIR/script-syntax.log" bash -lc "for f in \"$SCRIPT_ROOT\"/*.sh; do bash -n \"\$f\"; done"
run_check critical bootstrap-marker "Validate bootstrap baseline marker exists." "$ARTIFACT_DIR/bootstrap-marker.log" require_bootstrap_marker
run_check critical config-presence "Validate product config file exists for environment." "$ARTIFACT_DIR/config-presence.log" require_runtime_file "$CONFIG_PATH" "product configuration file"
run_check critical config-render-public "Render public runtime from product config." "$ARTIFACT_DIR/config-render-public.log" check_render_public_runtime
run_check critical config-render-inventory "Render runtime inventory from product config." "$ARTIFACT_DIR/config-render-inventory.log" check_render_runtime_inventory
run_check critical runtime-override-file "Ensure runtime override file exists." "$ARTIFACT_DIR/runtime-override.log" check_runtime_override_file
run_check critical secret-presence "Validate required secret keys are present." "$ARTIFACT_DIR/secret-presence.log" check_secret_keys
run_check critical ansible-inventory "Validate runtime inventory parsing." "$ARTIFACT_DIR/ansible-inventory.log" ansible-inventory -i "$INVENTORY_RUNTIME_PATH" --list
run_check critical ansible-syntax "Validate playbook syntax with runtime vars and secrets." "$ARTIFACT_DIR/ansible-syntax.log" ansible-playbook -i "$INVENTORY_RUNTIME_PATH" "$SCRIPT_ROOT/../ansible/site.yml" --syntax-check --extra-vars "@$PUBLIC_RUNTIME_PATH" --extra-vars "@$OVERRIDE_RUNTIME_PATH" --extra-vars "@$SECRET_PATH"
run_check critical docs-navigation "Validate documentation navigation chain." "$ARTIFACT_DIR/docs-navigation.log" check_docs_navigation
run_check critical docs-precedence "Validate documented precedence and secret policy." "$ARTIFACT_DIR/docs-precedence.log" check_runtime_precedence_docs
if [[ "$ENVIRONMENT" == "staging" ]]; then
  run_check critical staging-certification-evidence "Validate staging certification gate and evidence linkage." "$ARTIFACT_DIR/staging-certification-evidence.log" check_staging_certification_artifacts
fi
if [[ "$ENVIRONMENT" == "production" ]]; then
  run_check critical production-policy-contract "Validate production security policy contract." "$ARTIFACT_DIR/production-policy-contract.log" check_production_policy_contract
fi

write_report_markdown
write_report_json

if ((critical_failures > 0)); then
  echo "Readiness failed with critical issues."
  echo "Report (MD): $REPORT_MD"
  echo "Report (JSON): $REPORT_JSON"
  exit 1
fi

echo "Readiness completed successfully."
echo "Report (MD): $REPORT_MD"
echo "Report (JSON): $REPORT_JSON"
exit 0
