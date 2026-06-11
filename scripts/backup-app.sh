#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"

BACKUP_ROOT_DEFAULT="${BACKUP_ROOT:-/tmp/glpi-backups}"

MODE="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

TARGET="all"
GLPI_DIR=""
OUTPUT_DIR="$BACKUP_ROOT_DEFAULT"
ARTIFACT_PATH=""
ARTIFACT_NAME=""

EXCLUDE_APP_CSV=""
EXCLUDE_DB_TABLES_DATA_CSV=""

ENCRYPT_OUTPUT="0"
PASSPHRASE_FILE=""

FORCE_RESTORE="0"
DB_RECREATE="0"

DB_HOST=""
DB_PORT=""
DB_USER=""
DB_PASSWORD=""
DB_NAME=""

WORKDIR=""
BUNDLE_ROOT=""
BUNDLE_META_DIR=""
BUNDLE_PAYLOAD_DIR=""

GLPI_CONFIG_DIR=""
GLPI_VAR_DIR=""
GLPI_LOG_DIR=""
GLPI_MARKETPLACE_DIR=""
GLPI_CONFIG_DB_FILE=""
GLPI_CORE_DATA_DIR=""
GLPI_CORE_SYMLINK_PATH=""

APP_PAYLOAD_PATH=""
DB_DUMP_PATH=""
APP_PATHS_FILE=""
APP_EXCLUDE_FILE=""
DB_EXCLUDE_TABLES_FILE=""
MANIFEST_PATH=""
RESTORE_NOTES_PATH=""

APP_PAYLOAD_SHA256=""
DB_DUMP_SHA256=""
FINAL_ARTIFACT_SHA256=""
APP_RESTORE_MEMBER_FILTER_FILE=""

REQUIRE_APP="0"
REQUIRE_DB="0"

declare -a APP_TAR_EXCLUDES=()
declare -a APP_EXCLUDE_RESOLVED=()
declare -a DB_EXCLUDE_TABLES_DATA=()

declare -A APP_SEEN_PATHS=()

auto_cleanup() {
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap auto_cleanup EXIT

usage() {
  cat <<USAGE
Uso:
  sudo ./${SCRIPT_NAME} backup  --target app|db|all [opções]
  sudo ./${SCRIPT_NAME} restore --target app|db|all [opções]

Comandos:
  backup                     Gera artefato único com app/db/metadados
  restore                    Restaura app/db a partir do artefato

Parâmetros comuns:
  --target <app|db|all>      Escopo de execução. Padrão: all
  --glpi-dir <path>          Diretório core do GLPI (auto-detecta se omitido)
  --db-host <host|socket>    Host/socket do banco
  --db-port <port>           Porta do banco
  --db-user <user>           Usuário do banco
  --db-password <password>   Senha do banco (se omitida, solicita em runtime)
  --db-name <name>           Nome da base GLPI
  --passphrase-file <path>   Arquivo com passphrase para criptografia/descriptografia
                             (se omitido com --encrypt ou .enc, solicita em runtime)
  -h, --help                 Exibe esta ajuda

Opções de backup:
  --output-dir <path>        Diretório de saída. Padrão: /tmp/glpi-backups
  --artifact <path>          Caminho final do artefato (sobrescreve output-dir/nome)
  --artifact-name <name>     Nome do artefato .tar.gz (sem caminho)
  --exclude-app <csv>        Exclusões app CSV (prefixo de área ou absoluto)
                             Prefixos aceitos: core/,config/,var/,log/,plugins/,marketplace/
  --exclude-db-tables-data <csv>
                             Tabelas para excluir somente dados no dump
  --encrypt                  Criptografa artefato final com openssl (passphrase em runtime)

Opções de restore:
  --artifact <path>          Artefato de entrada (.tar.gz ou .enc)
  --force                    App: permite sobrescrever estruturas já existentes
  --db-recreate              DB: drop/create da base antes do import

Exemplos:
  sudo ./${SCRIPT_NAME} backup --target all
  sudo ./${SCRIPT_NAME} backup --target app --exclude-app "var/_cache,var/_sessions"
  sudo ./${SCRIPT_NAME} backup --target db --exclude-db-tables-data "glpi_logs,glpi_sessions"
  sudo ./${SCRIPT_NAME} backup --target all --encrypt
  sudo ./${SCRIPT_NAME} restore --target app --artifact /tmp/glpi-backups/arquivo.tar.gz --force
  sudo ./${SCRIPT_NAME} restore --target db --artifact /tmp/glpi-backups/arquivo.tar.gz --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
USAGE
}

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

split_csv() {
  local csv="$1"
  local -n out_ref="$2"
  out_ref=()

  local raw item
  IFS=',' read -r -a raw <<< "$csv"
  for item in "${raw[@]}"; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    out_ref+=("$item")
  done
}

is_valid_target() {
  case "$1" in
    app|db|all) return 0 ;;
    *) return 1 ;;
  esac
}

set_target_flags() {
  case "$TARGET" in
    app)
      REQUIRE_APP="1"
      REQUIRE_DB="0"
      ;;
    db)
      REQUIRE_APP="0"
      REQUIRE_DB="1"
      ;;
    all)
      REQUIRE_APP="1"
      REQUIRE_DB="1"
      ;;
    *)
      die "Target inválido: $TARGET"
      ;;
  esac
}

preflight_line() {
  local level="$1"
  local status="$2"
  local message="$3"
  printf '[PREFLIGHT][%s][%s] %s\n' "$level" "$status" "$message"
}

preflight_mandatory_command() {
  local cmd="$1"
  if command_exists "$cmd"; then
    preflight_line "mandatory" "ok" "comando '$cmd' disponível"
  else
    preflight_line "mandatory" "fail" "comando '$cmd' ausente"
    return 1
  fi
}

preflight_optional_command() {
  local cmd="$1"
  if command_exists "$cmd"; then
    preflight_line "optional" "ok" "comando '$cmd' disponível"
  else
    preflight_line "optional" "warn" "comando '$cmd' ausente"
  fi
}

run_preflight() {
  local mode="$1"
  local target="$2"
  local encrypted_input="${3:-0}"

  local mandatory_failures=0

  preflight_line "mandatory" "check" "iniciando validações para ${mode}/${target}"

  if [[ "$mode" == "backup" || "$mode" == "restore" ]]; then
    if [[ "$target" == "app" || "$target" == "all" ]]; then
      if [[ "${EUID}" -ne 0 ]]; then
        preflight_line "mandatory" "fail" "execute como root para ler/escrever caminhos protegidos do app"
        mandatory_failures=$((mandatory_failures + 1))
      else
        preflight_line "mandatory" "ok" "execução root validada para escopo app"
      fi
    fi

    if ! preflight_mandatory_command tar; then
      mandatory_failures=$((mandatory_failures + 1))
    fi
    if ! preflight_mandatory_command gzip; then
      mandatory_failures=$((mandatory_failures + 1))
    fi

    if [[ "$mode" == "backup" && ( "$target" == "db" || "$target" == "all" ) ]]; then
      if ! preflight_mandatory_command mysqldump; then
        mandatory_failures=$((mandatory_failures + 1))
      fi
    fi

    if [[ "$mode" == "restore" && ( "$target" == "db" || "$target" == "all" ) ]]; then
      if ! preflight_mandatory_command mysql; then
        mandatory_failures=$((mandatory_failures + 1))
      fi
    fi

    if [[ "$ENCRYPT_OUTPUT" == "1" || "$encrypted_input" == "1" ]]; then
      if ! preflight_mandatory_command openssl; then
        mandatory_failures=$((mandatory_failures + 1))
      fi
    fi

    preflight_optional_command sha256sum
    preflight_optional_command php
  fi

  if (( mandatory_failures > 0 )); then
    die "Pre-flight falhou com ${mandatory_failures} item(ns) mandatory. Corrija antes de continuar."
  fi
}

prepare_workdir() {
  WORKDIR="$(mktemp -d)"
  BUNDLE_ROOT="$WORKDIR/bundle"
  BUNDLE_META_DIR="$BUNDLE_ROOT/meta"
  BUNDLE_PAYLOAD_DIR="$BUNDLE_ROOT/payload"

  mkdir -p "$BUNDLE_META_DIR" "$BUNDLE_PAYLOAD_DIR"

  APP_PATHS_FILE="$BUNDLE_META_DIR/app-paths.txt"
  APP_EXCLUDE_FILE="$BUNDLE_META_DIR/app-excludes.txt"
  DB_EXCLUDE_TABLES_FILE="$BUNDLE_META_DIR/db-exclude-tables-data.txt"
  MANIFEST_PATH="$BUNDLE_META_DIR/MANIFEST.txt"
  RESTORE_NOTES_PATH="$BUNDLE_META_DIR/RESTORE.txt"
}

php_constant_from_file() {
  local file="$1"
  local constant="$2"
  [[ -f "$file" ]] || return 1
  command_exists php || return 1

  php -r '
    $file = $argv[1];
    $constant = $argv[2];
    if (!is_file($file)) { exit(1); }
    @include $file;
    if (defined($constant)) { echo constant($constant); }
  ' "$file" "$constant" 2>/dev/null || true
}

find_glpi_dir() {
  if [[ -n "$GLPI_DIR" ]]; then
    [[ -d "$GLPI_DIR" ]] || die "GLPI_DIR informado não existe: $GLPI_DIR"
    printf '%s' "${GLPI_DIR%/}"
    return 0
  fi

  local candidates=(
    /usr/share/glpi
    /var/www/glpi
    /var/www/html/glpi
    /opt/glpi
    /srv/glpi
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/bin/console" || -f "$candidate/public/index.php" || -f "$candidate/inc/define.php" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  local found=""
  found="$(find /usr/share /var/www /opt /srv -maxdepth 5 -type f -path '*/bin/console' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$(dirname "$(dirname "$found")")"
    return 0
  fi

  return 1
}

read_db_var() {
  local config_file="$1"
  local var_name="$2"
  command_exists php || return 1
  [[ -f "$config_file" ]] || return 1

  php -r '
    $file = $argv[1];
    $var = $argv[2];
    @include $file;
    if (isset($$var)) { echo base64_encode((string) $$var); }
  ' "$config_file" "$var_name" 2>/dev/null | base64 -d 2>/dev/null || true
}

resolve_glpi_layout() {
  local downstream_file local_define_file config_dir var_dir log_dir marketplace_dir config_db_file

  GLPI_DIR="$(find_glpi_dir)" || die "Não foi possível localizar GLPI. Informe --glpi-dir."
  GLPI_DIR="${GLPI_DIR%/}"

  downstream_file="$GLPI_DIR/inc/downstream.php"
  config_dir=""

  if [[ -f "$downstream_file" ]]; then
    config_dir="$(php_constant_from_file "$downstream_file" GLPI_CONFIG_DIR || true)"
  fi

  if [[ -z "$config_dir" ]]; then
    if [[ -f /etc/glpi/config_db.php || -f /etc/glpi/local_define.php ]]; then
      config_dir="/etc/glpi"
    else
      config_dir="$GLPI_DIR/config"
    fi
  fi
  config_dir="${config_dir%/}"

  local_define_file="$config_dir/local_define.php"

  var_dir="$(php_constant_from_file "$local_define_file" GLPI_VAR_DIR || true)"
  [[ -n "$var_dir" ]] || var_dir="$GLPI_DIR/files"
  var_dir="${var_dir%/}"

  log_dir="$(php_constant_from_file "$local_define_file" GLPI_LOG_DIR || true)"
  if [[ -z "$log_dir" ]]; then
    if [[ -d /var/log/glpi ]]; then
      log_dir="/var/log/glpi"
    else
      log_dir="$var_dir/_log"
    fi
  fi
  log_dir="${log_dir%/}"

  marketplace_dir="$(php_constant_from_file "$local_define_file" GLPI_MARKETPLACE_DIR || true)"
  [[ -n "$marketplace_dir" ]] && marketplace_dir="${marketplace_dir%/}"

  config_db_file=""
  local candidate
  for candidate in "$config_dir/config_db.php" "$GLPI_DIR/config/config_db.php"; do
    if [[ -f "$candidate" ]]; then
      config_db_file="$candidate"
      break
    fi
  done

  GLPI_CONFIG_DIR="$config_dir"
  GLPI_VAR_DIR="$var_dir"
  GLPI_LOG_DIR="$log_dir"
  GLPI_MARKETPLACE_DIR="$marketplace_dir"
  GLPI_CONFIG_DB_FILE="$config_db_file"

  GLPI_CORE_DATA_DIR="$GLPI_DIR"
  GLPI_CORE_SYMLINK_PATH=""
  if [[ -L "$GLPI_DIR" ]]; then
    local resolved_glpi_dir
    resolved_glpi_dir="$(readlink -f "$GLPI_DIR" 2>/dev/null || true)"
    if [[ -n "$resolved_glpi_dir" && -d "$resolved_glpi_dir" ]]; then
      GLPI_CORE_DATA_DIR="${resolved_glpi_dir%/}"
      GLPI_CORE_SYMLINK_PATH="$GLPI_DIR"
    fi
  fi
}

add_path_include() {
  local include_file="$1"
  local path="$2"

  [[ -n "$path" ]] || return 0
  [[ -e "$path" || -L "$path" ]] || return 0

  local rel="${path#/}"
  [[ -n "$rel" ]] || return 0

  if [[ -z "${APP_SEEN_PATHS[$rel]+x}" ]]; then
    APP_SEEN_PATHS["$rel"]=1
    printf '%s\0' "$rel" >> "$include_file"
  fi
}

add_tar_exclude() {
  local path="$1"
  [[ -n "$path" ]] || return 0

  local rel="${path#/}"
  [[ -n "$rel" ]] || return 0

  APP_TAR_EXCLUDES+=("--exclude=$rel" "--exclude=$rel/*")
}

add_glob_includes() {
  local include_file="$1"
  local pattern="$2"
  local match=""

  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    add_path_include "$include_file" "$match"
  done < <(compgen -G "$pattern" || true)
}

add_grep_matches_as_includes() {
  local include_file="$1"
  local search_dirs=("$@")
  search_dirs=("${search_dirs[@]:1}")

  local dir match
  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      add_path_include "$include_file" "$match"
    done < <(grep -RIl --exclude='*.dpkg-*' --exclude='*.ucf-*' --exclude='*.swp' -E 'glpi|GLPI' "$dir" 2>/dev/null || true)
  done
}

resolve_app_exclusion() {
  local token="$1"

  if [[ "$token" == /* ]]; then
    printf '%s' "${token%/}"
    return 0
  fi

  local prefix suffix base
  prefix="${token%%/*}"
  suffix="${token#*/}"

  if [[ "$token" == "$prefix" ]]; then
    suffix=""
  fi

  case "$prefix" in
    core) base="${GLPI_CORE_DATA_DIR:-$GLPI_DIR}" ;;
    config) base="$GLPI_CONFIG_DIR" ;;
    var) base="$GLPI_VAR_DIR" ;;
    log) base="$GLPI_LOG_DIR" ;;
    plugins) base="${GLPI_CORE_DATA_DIR:-$GLPI_DIR}/plugins" ;;
    marketplace)
      if [[ -n "$GLPI_MARKETPLACE_DIR" ]]; then
        base="$GLPI_MARKETPLACE_DIR"
      else
        base="${GLPI_CORE_DATA_DIR:-$GLPI_DIR}/marketplace"
      fi
      ;;
    *)
      die "Exclusão de app inválida: '$token'. Use prefixo de área (core/config/var/log/plugins/marketplace) ou caminho absoluto."
      ;;
  esac

  if [[ -z "$suffix" || "$suffix" == "$prefix" ]]; then
    printf '%s' "${base%/}"
  else
    printf '%s' "${base%/}/${suffix}"
  fi
}

apply_app_exclusions() {
  local -a items=()
  split_csv "$EXCLUDE_APP_CSV" items

  : > "$APP_EXCLUDE_FILE"

  local token resolved
  for token in "${items[@]}"; do
    resolved="$(resolve_app_exclusion "$token")"
    APP_EXCLUDE_RESOLVED+=("$resolved")
    add_tar_exclude "$resolved"
    printf '%s -> %s\n' "$token" "$resolved" >> "$APP_EXCLUDE_FILE"
  done
}

resolve_db_credentials_for_backup() {
  if [[ -n "$DB_HOST" && -n "$DB_USER" && -n "$DB_NAME" ]]; then
    return 0
  fi

  if [[ -z "$GLPI_CONFIG_DB_FILE" ]]; then
    resolve_glpi_layout
  fi

  [[ -n "$GLPI_CONFIG_DB_FILE" ]] || die "config_db.php não encontrado e credenciais DB não foram informadas por parâmetro."

  [[ -n "$DB_HOST" ]] || DB_HOST="$(read_db_var "$GLPI_CONFIG_DB_FILE" dbhost)"
  [[ -n "$DB_USER" ]] || DB_USER="$(read_db_var "$GLPI_CONFIG_DB_FILE" dbuser)"
  [[ -n "$DB_PASSWORD" ]] || DB_PASSWORD="$(read_db_var "$GLPI_CONFIG_DB_FILE" dbpassword)"
  [[ -n "$DB_NAME" ]] || DB_NAME="$(read_db_var "$GLPI_CONFIG_DB_FILE" dbdefault)"
  [[ -n "$DB_PORT" ]] || DB_PORT="$(read_db_var "$GLPI_CONFIG_DB_FILE" dbport)"

  if [[ -z "$DB_PORT" && "$DB_HOST" == *:* && "$DB_HOST" != *::* && "$DB_HOST" != /* ]]; then
    DB_PORT="${DB_HOST##*:}"
    DB_HOST="${DB_HOST%:*}"
  fi

  [[ -n "$DB_HOST" ]] || DB_HOST="localhost"

  [[ -n "$DB_USER" ]] || die "Usuário DB não identificado. Informe --db-user."
  [[ -n "$DB_NAME" ]] || die "Nome da base DB não identificado. Informe --db-name."

  if [[ -z "$DB_PASSWORD" ]]; then
    if [[ ! -t 0 ]]; then
      die "Senha do usuário DB não informada para backup. Use --db-password ou execute interativamente."
    fi
    if ! read -r -s -p "Senha do usuário DB para backup (${DB_USER}): " DB_PASSWORD; then
      echo
      die "Falha ao ler senha do usuário DB para backup."
    fi
    echo
    [[ -n "$DB_PASSWORD" ]] || die "Senha do usuário DB para backup não pode ficar vazia."
  fi
}

ensure_db_restore_params_explicit() {
  [[ -n "$DB_HOST" ]] || die "No restore DB informe --db-host."
  [[ -n "$DB_USER" ]] || die "No restore DB informe --db-user."
  [[ -n "$DB_NAME" ]] || die "No restore DB informe --db-name."

  if [[ -z "$DB_PASSWORD" ]]; then
    if [[ ! -t 0 ]]; then
      die "Senha do usuário DB não informada para restore. Use --db-password ou execute interativamente."
    fi
    if ! read -r -s -p "Senha do usuário DB para restore (${DB_USER}): " DB_PASSWORD; then
      echo
      die "Falha ao ler senha do usuário DB para restore."
    fi
    echo
    [[ -n "$DB_PASSWORD" ]] || die "Senha do usuário DB para restore não pode ficar vazia."
  fi

  if [[ ! "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    die "Nome de base inválido para restore: '$DB_NAME'."
  fi
}

create_mysql_client_cnf() {
  local cnf_path="$1"
  local host="$2"
  local port="$3"
  local user="$4"
  local password="$5"

  {
    printf '[client]\n'
    printf 'user=%s\n' "$user"
    printf 'password=%s\n' "$password"

    if [[ "$host" == /* || "$host" == *.sock ]]; then
      printf 'socket=%s\n' "$host"
    else
      printf 'host=%s\n' "$host"
      if [[ -n "$port" ]]; then
        printf 'port=%s\n' "$port"
      fi
    fi

    printf 'default-character-set=utf8mb4\n'
  } > "$cnf_path"

  chmod 600 "$cnf_path"
}

resolve_encryption_passphrase() {
  local purpose="$1"
  local passphrase=""

  if [[ -n "$PASSPHRASE_FILE" ]]; then
    [[ -f "$PASSPHRASE_FILE" ]] || die "Arquivo de passphrase não encontrado: $PASSPHRASE_FILE"
    passphrase="$(head -n 1 "$PASSPHRASE_FILE" || true)"
  else
    read -r -s -p "Passphrase para ${purpose}: " passphrase
    echo
  fi

  [[ -n "$passphrase" ]] || die "Passphrase vazia não é permitida."
  printf '%s' "$passphrase"
}

write_manifest() {
  {
    echo "manifest_version=1"
    echo "created_at=$TIMESTAMP"
    echo "hostname=$HOSTNAME_SHORT"
    echo "mode=backup"
    echo "target=$TARGET"
    echo "glpi_dir=$GLPI_DIR"
    echo "glpi_core_data_dir=$GLPI_CORE_DATA_DIR"
    echo "glpi_core_symlink_path=$GLPI_CORE_SYMLINK_PATH"
    echo "config_dir=$GLPI_CONFIG_DIR"
    echo "var_dir=$GLPI_VAR_DIR"
    echo "log_dir=$GLPI_LOG_DIR"
    echo "marketplace_dir=$GLPI_MARKETPLACE_DIR"
    echo "config_db_file=$GLPI_CONFIG_DB_FILE"
    echo "exclude_app_csv=$EXCLUDE_APP_CSV"
    echo "exclude_db_tables_data_csv=$EXCLUDE_DB_TABLES_DATA_CSV"
    echo "db_host=$DB_HOST"
    echo "db_port=$DB_PORT"
    echo "db_user=$DB_USER"
    echo "db_name=$DB_NAME"
    echo "encrypt_output=$ENCRYPT_OUTPUT"
    echo "app_payload_sha256=$APP_PAYLOAD_SHA256"
    echo "db_dump_sha256=$DB_DUMP_SHA256"
    echo "note=Backup pode ser parcial quando exclusões são usadas."
  } > "$MANIFEST_PATH"

  {
    echo "Restore notes"
    echo
    echo "1. O restore de app aplica caminhos absolutos originais a partir de payload/app-rootfs.tar"
    echo "2. O restore de DB exige credenciais explícitas via flags"
    echo "3. Sem --force, restore de app falha se detectar destino já populado"
    echo "4. Sem --db-recreate, restore DB falha se a base já tiver tabelas"
    echo "5. Valide permissões e conectividade após restore"
  } > "$RESTORE_NOTES_PATH"
}

compute_sha256() {
  local path="$1"
  if command_exists sha256sum; then
    sha256sum "$path" | awk '{print $1}'
  fi
}

create_app_payload() {
  resolve_glpi_layout

  local include_file="$WORKDIR/app-include.null"
  : > "$include_file"

  # Quando GLPI_DIR é symlink (ex.: /usr/share/glpi -> /usr/share/glpi-11.0.7),
  # arquivamos o diretório real para evitar falha de restore com caminhos filhos.
  add_path_include "$include_file" "$GLPI_CORE_DATA_DIR"
  if [[ -n "$GLPI_CORE_SYMLINK_PATH" ]]; then
    add_path_include "$include_file" "$GLPI_CORE_SYMLINK_PATH"
  fi
  add_path_include "$include_file" "$GLPI_CONFIG_DIR"
  add_path_include "$include_file" "$GLPI_VAR_DIR"
  add_path_include "$include_file" "$GLPI_LOG_DIR"
  add_path_include "$include_file" "$GLPI_CORE_DATA_DIR/plugins"
  add_path_include "$include_file" "$GLPI_CORE_DATA_DIR/marketplace"

  if [[ -n "$GLPI_MARKETPLACE_DIR" ]]; then
    add_path_include "$include_file" "$GLPI_MARKETPLACE_DIR"
  fi

  add_glob_includes "$include_file" "/etc/logrotate.d/*glpi*"
  add_glob_includes "$include_file" "/etc/systemd/system/*glpi*"
  add_glob_includes "$include_file" "/lib/systemd/system/*glpi*"

  add_grep_matches_as_includes "$include_file" /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly /var/spool/cron/crontabs
  add_grep_matches_as_includes "$include_file" /etc/nginx /etc/apache2 /etc/httpd /etc/lighttpd /etc/php /etc/php-fpm.d

  # Evita embutir o diretório de saída dentro do próprio backup.
  add_tar_exclude "$OUTPUT_DIR"

  if [[ -n "$EXCLUDE_APP_CSV" ]]; then
    apply_app_exclusions
  else
    : > "$APP_EXCLUDE_FILE"
  fi

  APP_PAYLOAD_PATH="$BUNDLE_PAYLOAD_DIR/app-rootfs.tar"

  local -a tar_extra=()
  tar --help 2>/dev/null | grep -q -- '--acls' && tar_extra+=(--acls)
  tar --help 2>/dev/null | grep -q -- '--xattrs' && tar_extra+=(--xattrs)
  tar --help 2>/dev/null | grep -q -- '--selinux' && tar_extra+=(--selinux)

  log "Gerando payload de app..."
  tar \
    --create \
    --file "$APP_PAYLOAD_PATH" \
    --preserve-permissions \
    --numeric-owner \
    --ignore-failed-read \
    --warning=no-file-changed \
    "${tar_extra[@]}" \
    "${APP_TAR_EXCLUDES[@]}" \
    --directory / \
    --null \
    --files-from "$include_file"

  chmod 600 "$APP_PAYLOAD_PATH"

  tr '\0' '\n' < "$include_file" | sed 's#^#/#' > "$APP_PATHS_FILE"

  APP_PAYLOAD_SHA256="$(compute_sha256 "$APP_PAYLOAD_PATH" || true)"
}

parse_db_exclude_tables_data() {
  DB_EXCLUDE_TABLES_DATA=()
  if [[ -z "$EXCLUDE_DB_TABLES_DATA_CSV" ]]; then
    : > "$DB_EXCLUDE_TABLES_FILE"
    return 0
  fi

  local -a items=()
  split_csv "$EXCLUDE_DB_TABLES_DATA_CSV" items

  local item
  for item in "${items[@]}"; do
    if [[ ! "$item" =~ ^[A-Za-z0-9_]+$ ]]; then
      die "Tabela inválida em --exclude-db-tables-data: '$item'"
    fi
    DB_EXCLUDE_TABLES_DATA+=("$item")
  done

  printf '%s\n' "${DB_EXCLUDE_TABLES_DATA[@]}" > "$DB_EXCLUDE_TABLES_FILE"
}

create_db_dump_payload() {
  resolve_db_credentials_for_backup
  parse_db_exclude_tables_data

  if ((${#DB_EXCLUDE_TABLES_DATA[@]} > 0)); then
    if ! mysqldump --help 2>/dev/null | grep -q -- '--ignore-table-data'; then
      die "mysqldump deste host não suporta --ignore-table-data, exigido para exclusão de dados por tabela."
    fi
  fi

  local mysql_cnf="$WORKDIR/mysql-backup.cnf"
  create_mysql_client_cnf "$mysql_cnf" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASSWORD"

  DB_DUMP_PATH="$BUNDLE_PAYLOAD_DIR/db.sql.gz"

  local -a ignore_table_data_args=()
  local table
  for table in "${DB_EXCLUDE_TABLES_DATA[@]}"; do
    ignore_table_data_args+=("--ignore-table-data=${DB_NAME}.${table}")
  done

  log "Gerando dump da base '$DB_NAME'..."
  local dump_error_file="$WORKDIR/mysqldump.err"
  if ! mysqldump \
      --defaults-extra-file="$mysql_cnf" \
      --single-transaction \
      --quick \
      --routines \
      --triggers \
      --events \
      --hex-blob \
      "${ignore_table_data_args[@]}" \
      "$DB_NAME" 2>"$dump_error_file" | gzip -9 > "$DB_DUMP_PATH"; then
    if grep -Eiq 'PROCESS privilege|tablespaces' "$dump_error_file"; then
      warn "mysqldump falhou ao exportar tablespaces sem privilégio PROCESS; tentando novamente com --no-tablespaces."
      rm -f "$DB_DUMP_PATH"
      mysqldump \
        --defaults-extra-file="$mysql_cnf" \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --no-tablespaces \
        "${ignore_table_data_args[@]}" \
        "$DB_NAME" | gzip -9 > "$DB_DUMP_PATH"
    else
      cat "$dump_error_file" >&2
      return 1
    fi
  fi

  chmod 600 "$DB_DUMP_PATH"
  DB_DUMP_SHA256="$(compute_sha256 "$DB_DUMP_PATH" || true)"
}

build_final_artifact_path() {
  if [[ -n "$ARTIFACT_PATH" ]]; then
    printf '%s' "$ARTIFACT_PATH"
    return 0
  fi

  mkdir -p "$OUTPUT_DIR"
  chmod 755 "$OUTPUT_DIR" 2>/dev/null || true

  local name="$ARTIFACT_NAME"
  if [[ -z "$name" ]]; then
    name="glpi-transfer-${HOSTNAME_SHORT}-${TIMESTAMP}.tar.gz"
  fi

  if [[ "$name" != *.tar.gz ]]; then
    name="${name}.tar.gz"
  fi

  printf '%s/%s' "${OUTPUT_DIR%/}" "$name"
}

package_backup_bundle() {
  local final_artifact
  final_artifact="$(build_final_artifact_path)"

  write_manifest

  log "Gerando artefato único..."
  tar -czf "$final_artifact" -C "$WORKDIR" bundle
  chmod 644 "$final_artifact"

  if [[ "$ENCRYPT_OUTPUT" == "1" ]]; then
    local passphrase passfile encrypted_artifact
    passphrase="$(resolve_encryption_passphrase "criptografar backup")"
    passfile="$WORKDIR/passphrase.txt"
    printf '%s' "$passphrase" > "$passfile"
    chmod 600 "$passfile"

    encrypted_artifact="${final_artifact}.enc"

    openssl enc -aes-256-cbc -pbkdf2 -iter 200000 \
      -salt \
      -in "$final_artifact" \
      -out "$encrypted_artifact" \
      -pass "file:${passfile}"

    chmod 644 "$encrypted_artifact"
    rm -f "$final_artifact"
    final_artifact="$encrypted_artifact"
  fi

  if command_exists sha256sum; then
    FINAL_ARTIFACT_SHA256="$(compute_sha256 "$final_artifact")"
    printf '%s  %s\n' "$FINAL_ARTIFACT_SHA256" "$(basename "$final_artifact")" > "${final_artifact}.sha256"
    chmod 644 "${final_artifact}.sha256"
  fi

  log "Backup concluído: $final_artifact"
  if [[ -n "$FINAL_ARTIFACT_SHA256" ]]; then
    log "SHA256 final: $FINAL_ARTIFACT_SHA256"
    log "Arquivo de checksum: ${final_artifact}.sha256"
  fi
}

extract_restore_artifact() {
  local artifact_input="$1"
  local extracted_artifact="$artifact_input"

  [[ -f "$artifact_input" ]] || die "Artefato não encontrado: $artifact_input"

  if [[ "$artifact_input" == *.enc ]]; then
    local passphrase passfile decrypted
    passphrase="$(resolve_encryption_passphrase "descriptografar backup")"
    passfile="$WORKDIR/passphrase.txt"
    printf '%s' "$passphrase" > "$passfile"
    chmod 600 "$passfile"

    decrypted="$WORKDIR/decrypted-artifact.tar.gz"

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
      -in "$artifact_input" \
      -out "$decrypted" \
      -pass "file:${passfile}"

    extracted_artifact="$decrypted"
  fi

  local extract_dir="$WORKDIR/extracted"
  mkdir -p "$extract_dir"

  tar -xzf "$extracted_artifact" -C "$extract_dir"

  BUNDLE_ROOT="$extract_dir/bundle"
  BUNDLE_META_DIR="$BUNDLE_ROOT/meta"
  BUNDLE_PAYLOAD_DIR="$BUNDLE_ROOT/payload"

  APP_PAYLOAD_PATH="$BUNDLE_PAYLOAD_DIR/app-rootfs.tar"
  DB_DUMP_PATH="$BUNDLE_PAYLOAD_DIR/db.sql.gz"
  APP_PATHS_FILE="$BUNDLE_META_DIR/app-paths.txt"
  MANIFEST_PATH="$BUNDLE_META_DIR/MANIFEST.txt"

  [[ -d "$BUNDLE_ROOT" ]] || die "Artefato inválido: diretório bundle ausente."
  [[ -d "$BUNDLE_META_DIR" ]] || die "Artefato inválido: diretório meta ausente."
  [[ -d "$BUNDLE_PAYLOAD_DIR" ]] || die "Artefato inválido: diretório payload ausente."
}

manifest_get() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  awk -v k="$key" '$0 ~ "^" k "=" { sub(/^[^=]*=/, ""); sub(/\r$/, ""); print; exit }' "$file"
}

verify_payload_checksums() {
  command_exists sha256sum || return 0

  local expected_app expected_db current_app current_db
  expected_app="$(manifest_get app_payload_sha256 "$MANIFEST_PATH")"
  expected_db="$(manifest_get db_dump_sha256 "$MANIFEST_PATH")"

  if [[ -n "$expected_app" && -f "$APP_PAYLOAD_PATH" ]]; then
    current_app="$(compute_sha256 "$APP_PAYLOAD_PATH")"
    [[ "$current_app" == "$expected_app" ]] || die "Checksum do payload app inválido."
    log "Checksum app validado."
  fi

  if [[ -n "$expected_db" && -f "$DB_DUMP_PATH" ]]; then
    current_db="$(compute_sha256 "$DB_DUMP_PATH")"
    [[ "$current_db" == "$expected_db" ]] || die "Checksum do dump DB inválido."
    log "Checksum DB validado."
  fi
}

prepare_legacy_symlink_compatible_member_filter() {
  [[ -f "$APP_PAYLOAD_PATH" ]] || return 0
  APP_RESTORE_MEMBER_FILTER_FILE=""

  local entries_file symlink_entries_file skip_symlink_members_file filtered_members_file member
  entries_file="$WORKDIR/app-payload-entries.txt"
  symlink_entries_file="$WORKDIR/app-payload-symlink-members.txt"
  skip_symlink_members_file="$WORKDIR/app-payload-skip-symlink-members.txt"
  filtered_members_file="$WORKDIR/app-payload-members-filtered.txt"

  tar -tf "$APP_PAYLOAD_PATH" > "$entries_file"
  : > "$symlink_entries_file"
  : > "$skip_symlink_members_file"

  tar -tvf "$APP_PAYLOAD_PATH" | awk '
    $1 ~ /^l/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "->" && i > 6) {
          member = $6
          for (j = 7; j < i; j++) {
            member = member " " $j
          }
          print member
          break
        }
      }
    }
  ' > "$symlink_entries_file"

  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    if [[ -L "/$member" && -d "/$member" ]]; then
      if awk -v p="${member}/" 'index($0, p) == 1 { found=1; exit } END { exit(found ? 0 : 1) }' "$entries_file"; then
        printf '%s\n' "$member" >> "$skip_symlink_members_file"
      fi
    fi
  done < "$symlink_entries_file"

  if [[ -s "$skip_symlink_members_file" ]]; then
    warn "Aplicando compatibilidade de restore para payload legado com symlink + subcaminhos."
    while IFS= read -r member; do
      [[ -n "$member" ]] || continue
      warn "  - ignorando entrada de symlink conflitante no payload: $member"
    done < "$skip_symlink_members_file"

    awk '
      FNR == NR {
        skip[$0] = 1
        next
      }
      {
        entries[++n] = $0
        if ($0 ~ /\/$/) {
          dirs[$0] = 1
        }
      }
      END {
        for (i = 1; i <= n; i++) {
          e = entries[i]
          if (e in skip) {
            continue
          }
          if (e ~ /\/$/) {
            print e
            continue
          }
          p = e
          redundant = 0
          while (p ~ /\//) {
            sub(/\/[^\/]*$/, "", p)
            if (p == "") {
              break
            }
            if ((p "/") in dirs) {
              redundant = 1
              break
            }
          }
          if (!redundant) {
            print e
          }
        }
      }
    ' "$skip_symlink_members_file" "$entries_file" > "$filtered_members_file"

    if [[ ! -s "$filtered_members_file" ]]; then
      die "Falha ao preparar lista de membros do payload para modo compatível de restore."
    fi

    APP_RESTORE_MEMBER_FILTER_FILE="$filtered_members_file"
  fi
}

check_restore_app_collisions() {
  [[ -f "$APP_PATHS_FILE" ]] || return 0

  local collisions_file="$WORKDIR/app-collisions.txt"
  : > "$collisions_file"

  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue

    if [[ -d "$path" ]]; then
      if find "$path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        printf '%s\n' "$path" >> "$collisions_file"
      fi
    elif [[ -e "$path" || -L "$path" ]]; then
      printf '%s\n' "$path" >> "$collisions_file"
    fi
  done < "$APP_PATHS_FILE"

  if [[ -s "$collisions_file" ]]; then
    warn "Restore app detectou caminhos existentes no destino."
    sed 's/^/  - /' "$collisions_file" >&2
    die "Use --force para permitir sobrescrita no restore de app."
  fi
}

check_restore_app_directory_type_conflicts() {
  [[ -f "$APP_PAYLOAD_PATH" ]] || return 0

  local required_dirs_file="$WORKDIR/app-required-dirs.txt"
  local conflicts_file="$WORKDIR/app-dir-type-conflicts.txt"
  : > "$required_dirs_file"
  : > "$conflicts_file"

  local entry normalized path parent current
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    normalized="${entry#./}"
    normalized="${normalized%/}"
    [[ -n "$normalized" ]] || continue

    if [[ "$entry" == */ ]]; then
      printf '%s\n' "$normalized" >> "$required_dirs_file"
      continue
    fi

    path="$normalized"
    parent="${path%/*}"
    if [[ "$parent" == "$path" ]]; then
      continue
    fi
    current="$parent"
    while [[ -n "$current" && "$current" != "." ]]; do
      printf '%s\n' "$current" >> "$required_dirs_file"
      if [[ "$current" == */* ]]; then
        current="${current%/*}"
      else
        break
      fi
    done
  done < <(tar -tf "$APP_PAYLOAD_PATH")

  sort -u "$required_dirs_file" -o "$required_dirs_file"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    path="/$path"
    if [[ ( -e "$path" || -L "$path" ) && ! -d "$path" ]]; then
      printf '%s\n' "$path" >> "$conflicts_file"
    fi
  done < "$required_dirs_file"

  if [[ -s "$conflicts_file" ]]; then
    warn "Restore app detectou conflito de tipo de caminho (arquivo onde deveria existir diretório)."
    sed 's/^/  - /' "$conflicts_file" >&2
    die "Corrija os caminhos acima (mover/remover arquivo conflitante) e execute o restore novamente."
  fi
}

restore_app_payload() {
  [[ -f "$APP_PAYLOAD_PATH" ]] || die "Payload de app ausente no artefato."

  prepare_legacy_symlink_compatible_member_filter
  check_restore_app_directory_type_conflicts

  if [[ "$FORCE_RESTORE" != "1" ]]; then
    check_restore_app_collisions
  fi

  log "Restaurando payload de app em caminhos originais..."
  local -a tar_restore_args=()
  if tar --help 2>/dev/null | grep -q -- '--warning'; then
    tar_restore_args+=(--warning=no-timestamp)
  fi
  if tar --help 2>/dev/null | grep -q -- '--keep-directory-symlink'; then
    tar_restore_args+=(--keep-directory-symlink)
  fi
  if [[ -n "$APP_RESTORE_MEMBER_FILTER_FILE" ]]; then
    if tar --help 2>/dev/null | grep -q -- '--verbatim-files-from'; then
      tar_restore_args+=(--verbatim-files-from)
    fi
    tar "${tar_restore_args[@]}" -xpf "$APP_PAYLOAD_PATH" -C / --files-from "$APP_RESTORE_MEMBER_FILTER_FILE"
  else
    tar "${tar_restore_args[@]}" -xpf "$APP_PAYLOAD_PATH" -C /
  fi
  log "Restore de app concluído."
}

restore_db_payload() {
  [[ -f "$DB_DUMP_PATH" ]] || die "Dump DB ausente no artefato."

  ensure_db_restore_params_explicit

  local mysql_cnf="$WORKDIR/mysql-restore.cnf"
  create_mysql_client_cnf "$mysql_cnf" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASSWORD"

  local table_count="0"
  table_count="$(mysql --defaults-extra-file="$mysql_cnf" --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "query_failed")"

  if [[ "$table_count" == "query_failed" ]]; then
    die "Não foi possível validar o estado atual da base '${DB_NAME}'."
  fi

  if [[ "$DB_RECREATE" == "1" ]]; then
    log "Recriando base '${DB_NAME}' (--db-recreate)..."
    mysql --defaults-extra-file="$mysql_cnf" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  else
    if [[ "$table_count" != "0" ]]; then
      die "Base '${DB_NAME}' já contém tabelas (${table_count}). Use --db-recreate para substituir."
    fi
  fi

  log "Importando dump da base '${DB_NAME}'..."
  gzip -dc "$DB_DUMP_PATH" | mysql --defaults-extra-file="$mysql_cnf" "$DB_NAME"
  log "Restore de DB concluído."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        [[ $# -ge 2 ]] || die "Informe valor para --target"
        TARGET="$2"
        shift 2
        ;;
      --glpi-dir)
        [[ $# -ge 2 ]] || die "Informe valor para --glpi-dir"
        GLPI_DIR="$2"
        shift 2
        ;;
      --output-dir)
        [[ $# -ge 2 ]] || die "Informe valor para --output-dir"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --artifact)
        [[ $# -ge 2 ]] || die "Informe valor para --artifact"
        ARTIFACT_PATH="$2"
        shift 2
        ;;
      --artifact-name)
        [[ $# -ge 2 ]] || die "Informe valor para --artifact-name"
        ARTIFACT_NAME="$2"
        shift 2
        ;;
      --exclude-app)
        [[ $# -ge 2 ]] || die "Informe valor para --exclude-app"
        EXCLUDE_APP_CSV="$2"
        shift 2
        ;;
      --exclude-db-tables-data)
        [[ $# -ge 2 ]] || die "Informe valor para --exclude-db-tables-data"
        EXCLUDE_DB_TABLES_DATA_CSV="$2"
        shift 2
        ;;
      --encrypt)
        ENCRYPT_OUTPUT="1"
        shift
        ;;
      --passphrase-file)
        [[ $# -ge 2 ]] || die "Informe valor para --passphrase-file"
        PASSPHRASE_FILE="$2"
        shift 2
        ;;
      --force)
        FORCE_RESTORE="1"
        shift
        ;;
      --db-recreate)
        DB_RECREATE="1"
        shift
        ;;
      --db-host)
        [[ $# -ge 2 ]] || die "Informe valor para --db-host"
        DB_HOST="$2"
        shift 2
        ;;
      --db-port)
        [[ $# -ge 2 ]] || die "Informe valor para --db-port"
        DB_PORT="$2"
        shift 2
        ;;
      --db-user)
        [[ $# -ge 2 ]] || die "Informe valor para --db-user"
        DB_USER="$2"
        shift 2
        ;;
      --db-password)
        [[ $# -ge 2 ]] || die "Informe valor para --db-password"
        DB_PASSWORD="$2"
        shift 2
        ;;
      --db-name)
        [[ $# -ge 2 ]] || die "Informe valor para --db-name"
        DB_NAME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Parâmetro inválido: $1"
        ;;
    esac
  done
}

run_backup() {
  set_target_flags
  run_preflight "backup" "$TARGET" "0"

  prepare_workdir

  if [[ "$REQUIRE_APP" == "1" ]]; then
    create_app_payload
  fi

  if [[ "$REQUIRE_DB" == "1" ]]; then
    create_db_dump_payload
  fi

  package_backup_bundle

  log "Resumo backup: target=$TARGET app=$REQUIRE_APP db=$REQUIRE_DB encrypt=$ENCRYPT_OUTPUT"
}

run_restore() {
  set_target_flags

  [[ -n "$ARTIFACT_PATH" ]] || die "No restore, informe --artifact <path>."

  local encrypted_input="0"
  if [[ "$ARTIFACT_PATH" == *.enc ]]; then
    encrypted_input="1"
  fi

  run_preflight "restore" "$TARGET" "$encrypted_input"

  prepare_workdir
  extract_restore_artifact "$ARTIFACT_PATH"
  verify_payload_checksums

  if [[ "$REQUIRE_APP" == "1" ]]; then
    restore_app_payload
  fi

  if [[ "$REQUIRE_DB" == "1" ]]; then
    restore_db_payload
  fi

  log "Resumo restore: target=$TARGET app=$REQUIRE_APP db=$REQUIRE_DB force=$FORCE_RESTORE db_recreate=$DB_RECREATE"
}

main() {
  if [[ -z "$MODE" ]]; then
    usage
    exit 1
  fi

  case "$MODE" in
    backup|restore)
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "Modo inválido: $MODE (use backup ou restore)"
      ;;
  esac

  parse_args "$@"

  is_valid_target "$TARGET" || die "Target inválido: $TARGET"

  case "$MODE" in
    backup) run_backup ;;
    restore) run_restore ;;
  esac
}

main "$@"
