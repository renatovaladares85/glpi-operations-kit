#!/usr/bin/env bash
set -euo pipefail

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
HOSTNAME_SAFE="$(printf '%s' "$HOSTNAME_SHORT" | tr -c 'A-Za-z0-9_.-' '_')"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_PATH="/tmp/glpi_redis_session_rollback_${HOSTNAME_SAFE}_${TIMESTAMP}.log"

touch "$LOG_PATH"
chmod 0600 "$LOG_PATH" >/dev/null 2>&1 || true
exec > >(tee -a "$LOG_PATH") 2>&1

PROBE_PATH=""
CHANGED="no"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

on_exit() {
  local code=$?
  if [[ -n "${PROBE_PATH:-}" && -f "$PROBE_PATH" ]]; then
    rm -f "$PROBE_PATH" || true
  fi
  if [[ "$code" -ne 0 ]]; then
    log "FAILED exit_code=$code"
    log "log_path=$LOG_PATH"
  fi
}
trap on_exit EXIT

run_cmd() {
  log "+ $*"
  "$@"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

systemctl_unit_exists() {
  local service="$1"
  systemctl list-unit-files "${service}.service" --no-legend >/dev/null 2>&1 \
    || systemctl status "$service" >/dev/null 2>&1 \
    || [[ -f "/etc/systemd/system/${service}.service" ]] \
    || [[ -f "/lib/systemd/system/${service}.service" ]] \
    || [[ -f "/usr/lib/systemd/system/${service}.service" ]]
}

detect_php_version() {
  local service="${GLPI_PHP_FPM_SERVICE:-}"
  local version=""

  if [[ -n "${GLPI_PHP_VERSION:-}" ]]; then
    printf '%s\n' "$GLPI_PHP_VERSION"
    return 0
  fi

  if [[ "$service" =~ php([0-9]+\.[0-9]+)-fpm ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ -d /etc/php ]]; then
    version="$(find /etc/php -maxdepth 2 -type d -path '/etc/php/*/fpm' -printf '%h\n' 2>/dev/null \
      | awk -F/ '{print $4}' \
      | sort -V \
      | tail -n 1)"
    if [[ -n "$version" ]]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  if command_exists php; then
    php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true
    return 0
  fi
}

detect_php_fpm_service() {
  local php_version="$1"
  local candidates=()
  [[ -n "${GLPI_PHP_FPM_SERVICE:-}" ]] && candidates+=("$GLPI_PHP_FPM_SERVICE")
  [[ -n "$php_version" ]] && candidates+=("php${php_version}-fpm")
  candidates+=("php-fpm")

  local service
  for service in "${candidates[@]}"; do
    if [[ -n "$service" ]] && systemctl_unit_exists "$service"; then
      printf '%s\n' "$service"
      return 0
    fi
  done
  fail "Unable to detect PHP-FPM service."
}

detect_php_fpm_test_bin() {
  local php_version="$1"
  local candidate
  for candidate in "php-fpm${php_version}" php-fpm; do
    if [[ -n "$candidate" ]] && command_exists "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  fail "Unable to find php-fpm test binary."
}

detect_glpi_path() {
  local candidates=(
    "/usr/share/glpi"
    "/var/www/glpi"
    "/opt/glpi"
  )
  [[ -n "${GLPI_PATH:-}" ]] && candidates+=("$GLPI_PATH")
  [[ -n "${PATH_GLPI_INSTALL_DIR:-}" ]] && candidates+=("$PATH_GLPI_INSTALL_DIR")

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" && ( -f "$candidate/bin/console" || -d "$candidate/public" || -f "$candidate/inc/define.php" ) ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  fail "Unable to detect GLPI path."
}

detect_session_ini_paths() {
  find /etc/php /etc/php.d -path '*/99-glpi-redis-session.ini' -type f 2>/dev/null || true
}

create_http_probe() {
  local glpi_path="$1"
  local public_dir="${glpi_path}/public"
  local probe_name="_session_probe_${TIMESTAMP}_$$.php"

  [[ -d "$public_dir" ]] || fail "GLPI public directory not found: $public_dir"
  PROBE_PATH="${public_dir}/${probe_name}"
  cat > "$PROBE_PATH" <<'PHP'
<?php
header('Content-Type: text/plain');
echo 'session.save_handler=' . ini_get('session.save_handler') . "\n";
echo 'session.save_path=' . ini_get('session.save_path') . "\n";
echo 'redis.extension_loaded=' . (extension_loaded('redis') ? '1' : '0') . "\n";
PHP
  chmod 0644 "$PROBE_PATH"
  printf '%s\n' "$probe_name"
}

validate_http_probe_files() {
  local glpi_path="$1"
  local probe_name
  local scheme="http"
  local port="${GLPI_WEB_HTTP_PORT:-80}"
  local host_header="${GLPI_WEB_HOST_HEADER:-localhost}"
  local output=""

  if [[ "${GLPI_TLS_MODE:-none}" != "none" ]]; then
    scheme="https"
    port="${GLPI_WEB_HTTPS_PORT:-443}"
  fi

  probe_name="$(create_http_probe "$glpi_path")"
  local url="${scheme}://127.0.0.1:${port}/${probe_name}"
  log "+ curl -k -fsS -H Host:${host_header} ${url}"
  output="$(curl -k -fsS -H "Host: ${host_header}" "$url")"
  printf '%s\n' "$output"

  printf '%s\n' "$output" | grep -Fxq "session.save_handler=files" \
    || fail "PHP-FPM HTTP probe did not report session.save_handler=files after rollback."

  rm -f "$PROBE_PATH"
  PROBE_PATH=""
}

main() {
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "Run as root or through Ansible become."
  fi
  command_exists systemctl || fail "systemctl is required."
  command_exists curl || fail "curl is required."

  local php_version php_fpm_service php_fpm_test_bin glpi_path removed_any="no"
  php_version="$(detect_php_version)"
  php_fpm_service="$(detect_php_fpm_service "$php_version")"
  php_fpm_test_bin="$(detect_php_fpm_test_bin "$php_version")"
  glpi_path="$(detect_glpi_path)"

  log "Detected php_version=${php_version:-unknown}"
  log "Detected php_fpm_service=$php_fpm_service"
  log "Detected glpi_path=$glpi_path"

  while IFS= read -r ini_path; do
    [[ -n "$ini_path" ]] || continue
    local backup_path="${ini_path}.rollback.${TIMESTAMP}.bak"
    run_cmd mv "$ini_path" "$backup_path"
    log "Moved session Redis INI to backup: $backup_path"
    removed_any="yes"
    CHANGED="yes"
  done < <(detect_session_ini_paths)

  if [[ "$removed_any" == "no" ]]; then
    log "No 99-glpi-redis-session.ini file found; nothing to remove."
  fi

  run_cmd "$php_fpm_test_bin" -t
  run_cmd systemctl restart "$php_fpm_service"
  validate_http_probe_files "$glpi_path"

  log "Redis server/cache data were not removed or flushed."
  printf 'log_path=%s\n' "$LOG_PATH"
  printf 'GLPI_REDIS_SESSION_ROLLBACK_CHANGED=%s\n' "$CHANGED"
}

main "$@"
