#!/usr/bin/env bash
set -euo pipefail

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
HOSTNAME_SAFE="$(printf '%s' "$HOSTNAME_SHORT" | tr -c 'A-Za-z0-9_.-' '_')"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_PATH="/tmp/glpi_redis_integration_${HOSTNAME_SAFE}_${TIMESTAMP}.log"

touch "$LOG_PATH"
chmod 0600 "$LOG_PATH" >/dev/null 2>&1 || true
exec > >(tee -a "$LOG_PATH") 2>&1

declare -a CHANGED_FILES=()
declare -a BACKUPS=()
BACKED_UP_PATHS="|"
CHANGED="no"
NEED_FPM_RESTART="no"
NEED_REDIS_RESTART="no"
PROBE_PATH=""

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

mark_changed() {
  CHANGED="yes"
}

run_cmd() {
  log "+ $*"
  "$@"
}

run_shell() {
  log "+ $*"
  bash -o pipefail -c "$*"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "Run as root or through Ansible become."
  fi
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

detect_os_family() {
  local id="" id_like=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  case " ${id} ${id_like} " in
    *debian*|*ubuntu*)
      printf 'debian\n'
      ;;
    *rhel*|*fedora*|*centos*|*rocky*|*alma*)
      printf 'rhel\n'
      ;;
    *)
      fail "Unsupported Linux distribution. Supported families: Debian/Ubuntu and RHEL/Rocky/Alma/CentOS."
      ;;
  esac
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

detect_redis_service() {
  local candidates=()
  [[ -n "${GLPI_REDIS_SERVICE:-}" ]] && candidates+=("$GLPI_REDIS_SERVICE")
  candidates+=("redis-server" "redis")

  local service
  for service in "${candidates[@]}"; do
    if [[ -n "$service" ]] && systemctl_unit_exists "$service"; then
      printf '%s\n' "$service"
      return 0
    fi
  done
  fail "Unable to detect Redis service."
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

detect_web_user() {
  local pool user
  for pool in /etc/php/*/fpm/pool.d/glpi.conf /etc/php/*/fpm/pool.d/www.conf /etc/php-fpm.d/glpi.conf /etc/php-fpm.d/www.conf; do
    [[ -f "$pool" ]] || continue
    user="$(awk -F= '/^[[:space:]]*user[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$pool")"
    if [[ -n "$user" ]] && id "$user" >/dev/null 2>&1; then
      printf '%s\n' "$user"
      return 0
    fi
  done

  if [[ -n "${GLPI_WEB_USER:-}" ]] && id "$GLPI_WEB_USER" >/dev/null 2>&1; then
    printf '%s\n' "$GLPI_WEB_USER"
    return 0
  fi

  for user in www-data apache nginx; do
    if id "$user" >/dev/null 2>&1; then
      printf '%s\n' "$user"
      return 0
    fi
  done
  fail "Unable to detect web/PHP-FPM user."
}

detect_redis_conf() {
  local candidate
  for candidate in "${GLPI_REDIS_CONF:-}" /etc/redis/redis.conf /etc/redis.conf; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  fail "Unable to find Redis configuration file."
}

detect_fpm_conf_dir() {
  local php_version="$1"
  if [[ -n "$php_version" && -d "/etc/php/${php_version}/fpm/conf.d" ]]; then
    printf '%s\n' "/etc/php/${php_version}/fpm/conf.d"
    return 0
  fi
  if [[ -d /etc/php.d ]]; then
    printf '%s\n' "/etc/php.d"
    return 0
  fi
  if [[ -n "$php_version" ]]; then
    install -d -m 0755 "/etc/php/${php_version}/fpm/conf.d"
    printf '%s\n' "/etc/php/${php_version}/fpm/conf.d"
    return 0
  fi
  fail "Unable to determine PHP-FPM conf.d directory."
}

backup_file_once() {
  local path="$1"
  local backup_path
  [[ -f "$path" ]] || return 0
  case "$BACKED_UP_PATHS" in
    *"|${path}|"*) return 0 ;;
  esac
  backup_path="${path}.glpi-redis.${TIMESTAMP}.bak"
  run_cmd cp -a "$path" "$backup_path"
  BACKUPS+=("$backup_path")
  BACKED_UP_PATHS="${BACKED_UP_PATHS}${path}|"
}

record_changed_file() {
  local path="$1"
  CHANGED_FILES+=("$path")
  mark_changed
}

write_file_if_changed() {
  local path="$1"
  local mode="$2"
  local owner="${3:-root}"
  local group="${4:-root}"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"

  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    chown "$owner:$group" "$path"
    chmod "$mode" "$path"
    return 0
  fi

  backup_file_once "$path"
  run_cmd install -o "$owner" -g "$group" -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  record_changed_file "$path"
}

set_config_directive() {
  local file="$1"
  local key="$2"
  local value="$3"
  local desired="${key} ${value}"
  local current=""

  current="$(grep -E "^[[:space:]]*${key}([[:space:]]|$)" "$file" | tail -n 1 | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' || true)"
  if [[ "$current" == "$desired" ]]; then
    return 0
  fi

  backup_file_once "$file"
  if grep -Eq "^[[:space:]]*${key}([[:space:]]|$)" "$file"; then
    run_cmd sed -i -E "s|^[[:space:]]*${key}([[:space:]].*)?$|${desired}|" "$file"
  else
    printf '\n%s\n' "$desired" >> "$file"
  fi
  record_changed_file "$file"
}

redis_bind_is_loopback_only() {
  local file="$1"
  local active_bind
  active_bind="$(grep -E '^[[:space:]]*bind[[:space:]]+' "$file" | tail -n 1 | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' || true)"
  [[ "$active_bind" == "bind 127.0.0.1" || "$active_bind" == "bind 127.0.0.1 ::1" || "$active_bind" == "bind ::1 127.0.0.1" ]]
}

configure_redis_local() {
  local redis_conf="$1"
  log "Configuring Redis for local GLPI use: $redis_conf"

  if ! redis_bind_is_loopback_only "$redis_conf"; then
    set_config_directive "$redis_conf" "bind" "127.0.0.1"
    NEED_REDIS_RESTART="yes"
  fi

  set_config_directive "$redis_conf" "protected-mode" "yes"
  [[ "${CHANGED_FILES[*]}" == *"$redis_conf"* ]] && NEED_REDIS_RESTART="yes"

  if [[ -n "${GLPI_REDIS_MAXMEMORY:-}" ]]; then
    set_config_directive "$redis_conf" "maxmemory" "$GLPI_REDIS_MAXMEMORY"
    NEED_REDIS_RESTART="yes"
  fi

  if [[ -n "${GLPI_REDIS_MAXMEMORY_POLICY:-}" ]]; then
    set_config_directive "$redis_conf" "maxmemory-policy" "$GLPI_REDIS_MAXMEMORY_POLICY"
    NEED_REDIS_RESTART="yes"
  fi
}

debian_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

rpm_pkg_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

php_has_redis_cli() {
  command_exists php && php -m 2>/dev/null | awk '{print tolower($0)}' | grep -Fxq redis
}

install_dependencies() {
  local os_family="$1"
  local php_version="$2"

  if [[ "$os_family" == "debian" ]]; then
    command_exists apt-get || fail "apt-get not found on Debian/Ubuntu family host."
    local packages=()
    local php_redis_pkg="php-redis"

    if [[ -n "$php_version" ]] && apt-cache show "php${php_version}-redis" >/dev/null 2>&1; then
      php_redis_pkg="php${php_version}-redis"
    fi

    debian_pkg_installed redis-server || packages+=("redis-server")
    php_has_redis_cli || debian_pkg_installed "$php_redis_pkg" || packages+=("$php_redis_pkg")

    if ((${#packages[@]} > 0)); then
      run_cmd apt-get update
      run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      mark_changed
      NEED_FPM_RESTART="yes"
    fi
    return 0
  fi

  if [[ "$os_family" == "rhel" ]]; then
    command_exists rpm || fail "rpm not found on RHEL family host."
    local installer=""
    if command_exists dnf; then
      installer="dnf"
    elif command_exists yum; then
      installer="yum"
    else
      fail "dnf/yum not found on RHEL family host."
    fi

    local redis_missing="no"
    rpm_pkg_installed redis || redis_missing="yes"
    if [[ "$redis_missing" == "yes" || ! php_has_redis_cli ]]; then
      local base_packages=()
      [[ "$redis_missing" == "yes" ]] && base_packages+=("redis")
      if ! php_has_redis_cli; then
        if ! run_cmd "$installer" install -y "${base_packages[@]}" php-pecl-redis; then
          run_cmd "$installer" install -y "${base_packages[@]}" php-redis
        fi
      else
        run_cmd "$installer" install -y "${base_packages[@]}"
      fi
      mark_changed
      NEED_FPM_RESTART="yes"
    fi
  fi
}

enable_service_now() {
  local service="$1"
  local was_active="unknown"
  local was_enabled="unknown"
  was_active="$(systemctl is-active "$service" 2>/dev/null || true)"
  was_enabled="$(systemctl is-enabled "$service" 2>/dev/null || true)"
  run_cmd systemctl enable --now "$service"
  if [[ "$was_active" != "active" || "$was_enabled" != "enabled" ]]; then
    mark_changed
  fi
}

restart_service() {
  local service="$1"
  run_cmd systemctl restart "$service"
  mark_changed
}

configure_session_ini() {
  local ini_path="$1"
  local locking="${GLPI_REDIS_SESSION_LOCKING:-0}"
  case "$locking" in
    0|1) ;;
    *) fail "GLPI_REDIS_SESSION_LOCKING must be 0 or 1." ;;
  esac

  write_file_if_changed "$ini_path" "0644" root root <<EOF
session.save_handler = redis
session.save_path = "tcp://127.0.0.1:6379?database=1&prefix=glpi_sess:&timeout=2.5&read_timeout=2.5"
redis.session.locking_enabled = ${locking}
redis.session.lock_retries = 10
redis.session.lock_wait_time = 2000
session.lazy_write = 1
EOF

  if [[ " ${CHANGED_FILES[*]} " == *" ${ini_path} "* ]]; then
    NEED_FPM_RESTART="yes"
  fi
}

run_as_web() {
  local web_user="$1"
  shift
  if [[ "$(id -u)" -eq 0 && -n "$web_user" ]] && command_exists runuser; then
    run_cmd runuser -u "$web_user" -- "$@"
  else
    run_cmd "$@"
  fi
}

run_as_web_capture() {
  local web_user="$1"
  shift
  log "+ as ${web_user}: $*"
  if [[ "$(id -u)" -eq 0 && -n "$web_user" ]] && command_exists runuser; then
    runuser -u "$web_user" -- "$@"
  else
    "$@"
  fi
}

console_has_command() {
  local commands="$1"
  local command_name="$2"
  printf '%s\n' "$commands" | awk '{print $1}' | grep -Fxq "$command_name"
}

configure_glpi_cache() {
  local glpi_path="$1"
  local web_user="$2"
  local php_bin="$3"
  local cache_dsn="${GLPI_REDIS_CACHE_DSN:-redis://127.0.0.1:6379/0}"
  local cache_prefix="${GLPI_REDIS_CACHE_PREFIX:-glpi_cache_${HOSTNAME_SAFE}:}"
  local console="${glpi_path}/bin/console"
  local commands=""

  if [[ "${GLPI_DEFER_SCHEMA_BOOTSTRAP:-false}" == "true" ]]; then
    log "GLPI cache console configuration deferred because DB schema bootstrap is deferred."
    return 0
  fi

  if [[ ! -f "$console" ]]; then
    log "GLPI cache configuration skipped safely: bin/console not found at $console."
    return 0
  fi

  if ! commands="$(run_as_web_capture "$web_user" "$php_bin" "$console" list --raw 2>/tmp/glpi_redis_console_${TIMESTAMP}.err)"; then
    log "GLPI cache configuration skipped safely: bin/console list failed."
    if [[ -s "/tmp/glpi_redis_console_${TIMESTAMP}.err" ]]; then
      sed 's/^/console: /' "/tmp/glpi_redis_console_${TIMESTAMP}.err" >&2 || true
    fi
    rm -f "/tmp/glpi_redis_console_${TIMESTAMP}.err"
    return 0
  fi
  rm -f "/tmp/glpi_redis_console_${TIMESTAMP}.err"

  if console_has_command "$commands" "cache:configure"; then
    run_as_web "$web_user" "$php_bin" "$console" cache:configure --context=core --dsn="$cache_dsn"
  elif console_has_command "$commands" "glpi:cache:configure"; then
    run_as_web "$web_user" "$php_bin" "$console" glpi:cache:configure --context=core --dsn="$cache_dsn"
  else
    log "GLPI cache configuration skipped safely: cache:configure command not available."
    return 0
  fi

  if console_has_command "$commands" "cache:set_namespace_prefix"; then
    run_as_web "$web_user" "$php_bin" "$console" cache:set_namespace_prefix "$cache_prefix"
  elif console_has_command "$commands" "glpi:cache:set_namespace_prefix"; then
    run_as_web "$web_user" "$php_bin" "$console" glpi:cache:set_namespace_prefix "$cache_prefix"
  else
    log "GLPI cache namespace prefix skipped safely: cache:set_namespace_prefix command not available."
  fi
}

configure_glpi_cron() {
  local glpi_path="$1"
  local web_user="$2"
  local php_bin="$3"
  local cron_php="${glpi_path}/front/cron.php"
  local cron_line="* * * * * ${web_user} ${php_bin} ${cron_php} >/dev/null 2>&1"

  if [[ ! -f "$cron_php" ]]; then
    log "GLPI cron skipped safely: $cron_php not found."
    return 0
  fi

  if [[ -f /etc/cron.d/glpi ]] && grep -Fxq "$cron_line" /etc/cron.d/glpi; then
    log "Preserving compatible /etc/cron.d/glpi entry."
    chmod 0644 /etc/cron.d/glpi
    return 0
  fi

  write_file_if_changed /etc/cron.d/glpi "0644" root root <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${cron_line}
EOF
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
$redis_locking = ini_get('redis.session.locking_enabled');
if ($redis_locking === false || $redis_locking === '') {
    $redis_locking = '0';
}
echo 'session.save_handler=' . ini_get('session.save_handler') . "\n";
echo 'session.save_path=' . ini_get('session.save_path') . "\n";
echo 'redis.session.locking_enabled=' . $redis_locking . "\n";
echo 'redis.session.lock_retries=' . ini_get('redis.session.lock_retries') . "\n";
echo 'redis.session.lock_wait_time=' . ini_get('redis.session.lock_wait_time') . "\n";
echo 'session.lazy_write=' . ini_get('session.lazy_write') . "\n";
echo 'redis.extension_loaded=' . (extension_loaded('redis') ? '1' : '0') . "\n";
echo 'opcache.enable=' . ini_get('opcache.enable') . "\n";
PHP
  chmod 0644 "$PROBE_PATH"
  printf '%s\n' "$probe_name"
}

validate_http_probe() {
  local glpi_path="$1"
  local probe_name
  local scheme="http"
  local port="${GLPI_WEB_HTTP_PORT:-80}"
  local host_header="${GLPI_WEB_HOST_HEADER:-localhost}"
  local output=""
  local expected_locking="${GLPI_REDIS_SESSION_LOCKING:-0}"

  if [[ "${GLPI_TLS_MODE:-none}" != "none" ]]; then
    scheme="https"
    port="${GLPI_WEB_HTTPS_PORT:-443}"
  fi

  probe_name="$(create_http_probe "$glpi_path")"
  local url="${scheme}://127.0.0.1:${port}/${probe_name}"
  log "+ curl -k -fsS -H Host:${host_header} ${url}"
  output="$(curl -k -fsS -H "Host: ${host_header}" "$url")"
  printf '%s\n' "$output"

  printf '%s\n' "$output" | grep -Fxq "session.save_handler=redis" \
    || fail "PHP-FPM HTTP probe did not report session.save_handler=redis."
  printf '%s\n' "$output" | grep -Eq '^session.save_path=.*127\.0\.0\.1:6379.*database=1' \
    || fail "PHP-FPM HTTP probe did not report Redis DB 1 in session.save_path."
  printf '%s\n' "$output" | grep -Fxq "redis.session.locking_enabled=${expected_locking}" \
    || fail "PHP-FPM HTTP probe did not report redis.session.locking_enabled=${expected_locking}."
  printf '%s\n' "$output" | grep -Fxq "redis.extension_loaded=1" \
    || fail "PHP-FPM HTTP probe did not report loaded Redis extension."

  rm -f "$PROBE_PATH"
  PROBE_PATH=""
}

validate_redis_state() {
  run_cmd redis-cli PING
  run_cmd redis-cli INFO keyspace
  run_cmd redis-cli -n 0 DBSIZE
  run_cmd redis-cli -n 1 DBSIZE
  run_shell "redis-cli -n 1 --scan --pattern 'glpi_sess:*' | head"
  log "Redis DB 1 glpi_sess:* keys appear only after real GLPI login/access creates PHP sessions."
}

print_summary() {
  log "Summary"
  printf 'hostname=%s\n' "$HOSTNAME_SHORT"
  printf 'php_version=%s\n' "${PHP_VERSION:-unknown}"
  printf 'php_fpm_service=%s\n' "${PHP_FPM_SERVICE:-unknown}"
  printf 'redis_service=%s\n' "${REDIS_SERVICE:-unknown}"
  printf 'glpi_path=%s\n' "${GLPI_PATH_DETECTED:-unknown}"
  printf 'web_user=%s\n' "${WEB_USER:-unknown}"
  printf 'changed_files=%s\n' "${CHANGED_FILES[*]:-(none)}"
  printf 'backups=%s\n' "${BACKUPS[*]:-(none)}"
  printf 'rollback=/usr/local/sbin/glpi-redis-session-rollback.sh\n'
  printf 'log_path=%s\n' "$LOG_PATH"
  printf 'GLPI_REDIS_INTEGRATION_CHANGED=%s\n' "$CHANGED"
}

main() {
  require_root
  command_exists systemctl || fail "systemctl is required."
  command_exists curl || fail "curl is required."

  OS_FAMILY="$(detect_os_family)"
  PHP_VERSION="$(detect_php_version)"
  GLPI_PATH_DETECTED="$(detect_glpi_path)"
  WEB_USER="$(detect_web_user)"
  PHP_BIN="${GLPI_PHP_BIN:-$(command -v php || true)}"
  [[ -n "$PHP_BIN" ]] || fail "php binary not found."

  log "Detected os_family=$OS_FAMILY"
  log "Detected php_version=${PHP_VERSION:-unknown}"
  log "Detected glpi_path=$GLPI_PATH_DETECTED"
  log "Detected web_user=$WEB_USER"

  install_dependencies "$OS_FAMILY" "$PHP_VERSION"

  PHP_VERSION="$(detect_php_version)"
  PHP_FPM_SERVICE="$(detect_php_fpm_service "$PHP_VERSION")"
  PHP_FPM_TEST_BIN="$(detect_php_fpm_test_bin "$PHP_VERSION")"
  REDIS_SERVICE="$(detect_redis_service)"
  REDIS_CONF="$(detect_redis_conf)"
  FPM_CONF_DIR="$(detect_fpm_conf_dir "$PHP_VERSION")"
  SESSION_INI="${FPM_CONF_DIR}/99-glpi-redis-session.ini"

  log "Detected php_fpm_service=$PHP_FPM_SERVICE"
  log "Detected redis_service=$REDIS_SERVICE"
  log "Detected redis_conf=$REDIS_CONF"
  log "Detected fpm_conf_dir=$FPM_CONF_DIR"

  configure_redis_local "$REDIS_CONF"
  enable_service_now "$REDIS_SERVICE"
  if [[ "$NEED_REDIS_RESTART" == "yes" ]]; then
    restart_service "$REDIS_SERVICE"
  fi

  php_has_redis_cli || fail "php -m does not report Redis extension."

  configure_session_ini "$SESSION_INI"
  run_cmd "$PHP_FPM_TEST_BIN" -t
  if [[ "$NEED_FPM_RESTART" == "yes" ]]; then
    restart_service "$PHP_FPM_SERVICE"
  else
    enable_service_now "$PHP_FPM_SERVICE"
  fi

  validate_redis_state
  configure_glpi_cache "$GLPI_PATH_DETECTED" "$WEB_USER" "$PHP_BIN"
  configure_glpi_cron "$GLPI_PATH_DETECTED" "$WEB_USER" "$PHP_BIN"
  validate_http_probe "$GLPI_PATH_DETECTED"

  print_summary
}

main "$@"
