#!/usr/bin/env bash
#
# migrate-site.sh — 把运行中的 Drupal 站点搬到另一台服务器，或在本机从备份包恢复。
#
# 代码以 GitHub 上的仓库为准。本脚本打包或恢复数据库与上传文件。
# export 默认不改数据库、不改上传文件、不改 settings.php。
# 任何覆盖数据库或上传文件的步骤都会先把现状备份到 /root。
# 本脚本不改写 Git 历史，也不把备份包上传到任何远程仓库。
#
# 日志：/var/log/xedc-migrate.log
# 导入验收：/root/xedc-migrate-report.txt
#
# 用法：
#   ./migrate-site.sh export   [--root /var/www/drupal] [--out /root/xedc-migrate] [--maintenance] [--yes]
#   ./migrate-site.sh import   --pack <包路径> --domain <域名> [--root /var/www/drupal] [--yes] [--force]
#   ./migrate-site.sh rollback --backup <import 前自动生成的备份文件> [--root /var/www/drupal] [--yes]

set -euo pipefail
set -E

COMMAND=""
ROOT="/var/www/drupal"
OUT="/root/xedc-migrate"
PACK=""
DOMAIN=""
BACKUP=""
MAINTENANCE=0
ASSUME_YES=0
FORCE=0
LOG="/var/log/xedc-migrate.log"
REPORT="/root/xedc-migrate-report.txt"
WORK=""
DRUSH=()
EXPORT_MAINT=0
IMPORT_MAINT=0
ROLLBACK_MAINT=0
OVERWRITE_STARTED=0
REPORT_WRITTEN=0
STEP_FAILED=0
PREMIGRATE_SQL=""
PREMIGRATE_FILES=""
FINAL_OVERALL="失败"
NEW_NODES="?"
OLD_NODES="?"
NEW_USERS="?"
OLD_USERS="?"
NEW_FILES="?"
OLD_FILES="?"
BOOTSTRAP_VALUE="Failed"
HTTP_CODE="?"
DB_PREFIX=""
IN_TRAP=0
LOGGING=0

usage() {
  cat <<'EOF'
用法：
  ./migrate-site.sh export   [--root /var/www/drupal] [--out /root/xedc-migrate] [--maintenance] [--yes]
  ./migrate-site.sh import   --pack <包路径> --domain <域名> [--root /var/www/drupal] [--yes] [--force]
  ./migrate-site.sh rollback --backup <import 前自动生成的备份文件> [--root /var/www/drupal] [--yes]

export    在旧服务器打包数据库和上传文件。默认不修改站点。
import    在新服务器导入，或在同一台服务器上从备份包恢复。覆盖前自动备份。
rollback  用 import 自动生成的 sql.gz 回到导入之前。必须同时给出 --yes，否则只打印本说明。

export 发现未提交改动或未出现在本机远端跟踪分支上的提交时，会列出明细并停止，除非带 --yes。
import 发现目标库已有节点，或存在 uid>1 的用户时，必须同时带 --force 和 --yes。
参数缺失、无法识别或写错时，只打印本说明，不读取站点、不写日志。
EOF
}

redact_stream() {
  sed -u -E \
    -e 's#(://[^[:space:]/@]+):[^[:space:]@]+@#\1:***@#g' \
    -e 's/(--password=)[^[:space:]]+/\1***/Ig' \
    -e 's/(--password[[:space:]]+)[^[:space:]]+/\1***/Ig' \
    -e 's/(DB_PASS=)[^[:space:]]+/\1***/g' \
    -e 's/(DRUPAL_ADMIN_PASS=)[^[:space:]]+/\1***/g' \
    -e "s/('password'[[:space:]]*=>[[:space:]]*')[^']*/\\1***/g" \
    -e 's/("password"[[:space:]]*=>[[:space:]]*")[^"]*/\1***/g' \
    -e 's/ghp_[A-Za-z0-9]+/ghp_***/g'
}

redact_file() {
  redact_stream <"$1"
}

log_line() {
  local stamp msg
  stamp=$(date '+%F %T')
  msg=$(printf '%s' "$*" | redact_stream)
  printf '[%s] %s\n' "$stamp" "$msg"
  if [[ "$LOGGING" -eq 1 ]]; then
    printf '[%s] %s\n' "$stamp" "$msg" >>"$LOG"
  fi
}

warn() {
  local stamp msg
  stamp=$(date '+%F %T')
  msg=$(printf '%s' "$*" | redact_stream)
  printf '[%s] 警告: %s\n' "$stamp" "$msg" >&2
  if [[ "$LOGGING" -eq 1 ]]; then
    printf '[%s] 警告: %s\n' "$stamp" "$msg" >>"$LOG"
  fi
}

log_err() {
  local stamp msg
  stamp=$(date '+%F %T')
  msg=$(printf '%s' "$*" | redact_stream)
  printf '[%s] 错误: %s\n' "$stamp" "$msg" >&2
  if [[ "$LOGGING" -eq 1 ]]; then
    printf '[%s] 错误: %s\n' "$stamp" "$msg" >>"$LOG"
  fi
}

die() {
  log_err "$*"
  exit 1
}

print_captured_error() {
  local err_file="$1"
  local out_file="${2:-}"
  printf '错误原文：\n' >&2
  if [[ -f "$err_file" ]]; then
    redact_file "$err_file" | tee -a "$LOG" >&2
  fi
  if [[ -n "$out_file" && -f "$out_file" && -s "$out_file" ]]; then
    redact_file "$out_file" | tee -a "$LOG" >&2
  fi
}

init_logging() {
  touch "$LOG"
  chmod 600 "$LOG"
  LOGGING=1
  log_line "开始 ${COMMAND}。根目录 ${ROOT}。"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf '错误: 请用 root 运行。\n' >&2
    exit 1
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "缺少命令 ${cmd}。"
    fi
  done
}

acquire_lock() {
  local lock="/var/lock/xedc-migrate.lock"
  if [[ ! -d /var/lock ]]; then
    lock="/root/xedc-migrate.lock"
  fi
  exec 9>"$lock"
  if ! flock -n 9; then
    die "已有 migrate-site.sh 在运行。"
  fi
}

on_err() {
  local line="$1"
  if [[ "$IN_TRAP" -eq 1 ]]; then
    return 0
  fi
  IN_TRAP=1
  log_err "第 ${line} 行的命令失败。若上面已有输出，那就是完整错误原文，不是截断后的堆栈。"
  IN_TRAP=0
}

restore_export_maintenance() {
  local err rc
  if [[ "$EXPORT_MAINT" -ne 1 ]]; then
    return 0
  fi
  EXPORT_MAINT=0
  if [[ "${#DRUSH[@]}" -eq 0 ]]; then
    warn "维护模式曾被打开，但当前没有可用的 drush，无法自动写回 0。"
    return 1
  fi
  err=$(mktemp)
  set +e
  "${DRUSH[@]}" sset system.maintenance_mode 0 >"$err" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "无法把 system.maintenance_mode 恢复为 0。"
    print_captured_error "$err"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  log_line "已将 system.maintenance_mode 恢复为 0。"
  return 0
}

on_exit() {
  local rc=$?
  set +e
  trap '' ERR
  IN_TRAP=1
  restore_export_maintenance
  if [[ "$rc" -ne 0 && ( "$IMPORT_MAINT" -eq 1 || "$ROLLBACK_MAINT" -eq 1 ) ]]; then
    printf '\n提示：脚本异常结束，维护模式仍是开启。没有静默改回公开访问。\n' >&2
    printf '请查看 %s。\n' "$LOG" >&2
    if [[ -n "$PREMIGRATE_SQL" ]]; then
      printf '若要回到覆盖前的数据：\n  %s rollback --backup %s --root %s --yes\n' "$0" "$PREMIGRATE_SQL" "$ROOT" >&2
    fi
    if [[ "${#DRUSH[@]}" -gt 0 ]]; then
      printf '确认站点可以公开后，再手动执行：\n  %s sset system.maintenance_mode 0\n' "${DRUSH[*]}" >&2
    fi
  fi
  if [[ "$rc" -ne 0 && "$OVERWRITE_STARTED" -eq 1 && "$REPORT_WRITTEN" -eq 0 ]]; then
    FINAL_OVERALL="失败"
    write_report || true
  fi
  if [[ -n "$WORK" && -d "$WORK" ]]; then
    case "$WORK" in
      /root/xedc-migrate-work.*) rm -rf -- "$WORK" ;;
    esac
  fi
  exit "$rc"
}

parse_args() {
  local arg
  if [[ "$#" -eq 0 ]]; then
    usage
    exit 2
  fi
  case "$1" in
    -h|--help|help)
      usage
      exit 0
      ;;
    export|import|rollback)
      COMMAND="$1"
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  while [[ "$#" -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --root|--out|--pack|--domain|--backup)
        if [[ "$#" -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
          usage
          exit 2
        fi
        case "$arg" in
          --root) ROOT="$2" ;;
          --out) OUT="$2" ;;
          --pack) PACK="$2" ;;
          --domain) DOMAIN="$2" ;;
          --backup) BACKUP="$2" ;;
        esac
        shift 2
        ;;
      --maintenance)
        if [[ "$COMMAND" != "export" ]]; then
          usage
          exit 2
        fi
        MAINTENANCE=1
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --force)
        if [[ "$COMMAND" != "import" ]]; then
          usage
          exit 2
        fi
        FORCE=1
        shift
        ;;
      *)
        usage
        exit 2
        ;;
    esac
  done
  case "$COMMAND" in
    export)
      if [[ -n "$PACK" || -n "$DOMAIN" || -n "$BACKUP" ]]; then
        usage
        exit 2
      fi
      ;;
    import)
      if [[ -z "$PACK" || -z "$DOMAIN" || -n "$BACKUP" ]]; then
        usage
        exit 2
      fi
      ;;
    rollback)
      if [[ -z "$BACKUP" || -n "$PACK" || -n "$DOMAIN" || "$ASSUME_YES" -ne 1 ]]; then
        usage
        exit 2
      fi
      ;;
  esac
  if [[ "$ROOT" != /* || "$ROOT" == "/" ]]; then
    usage
    exit 2
  fi
  case "$ROOT" in
    /root|/etc|/usr|/bin|/sbin|/var|/var/log|/tmp|/home|/dev|/proc|/sys)
      usage
      exit 2
      ;;
  esac
  ROOT=$(readlink -m "$ROOT")
  if [[ "$COMMAND" == "export" ]]; then
    if [[ "$OUT" != /* || "$OUT" == "/" ]]; then
      usage
      exit 2
    fi
    OUT=$(readlink -m "$OUT")
    case "$OUT" in
      "$ROOT"|"$ROOT"/*)
        printf '错误: --out 不能放在站点目录内。\n' >&2
        usage
        exit 2
        ;;
    esac
  fi
  if [[ "$COMMAND" == "import" ]]; then
    if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
      usage
      exit 2
    fi
    if [[ ! -f "$PACK" ]]; then
      printf '错误: 找不到包 %s\n' "$PACK" >&2
      usage
      exit 2
    fi
    PACK=$(readlink -f "$PACK")
  fi
  if [[ "$COMMAND" == "rollback" ]]; then
    case "$BACKUP" in
      *.sql.gz) ;;
      *)
        printf '错误: --backup 必须是以 .sql.gz 结尾的文件。\n' >&2
        usage
        exit 2
        ;;
    esac
    if [[ ! -f "$BACKUP" ]]; then
      printf '错误: 找不到备份 %s\n' "$BACKUP" >&2
      usage
      exit 2
    fi
    BACKUP=$(readlink -f "$BACKUP")
  fi
}

make_work() {
  WORK=$(mktemp -d /root/xedc-migrate-work.XXXXXX)
  chmod 700 "$WORK"
}

human_size() {
  awk -v n="$1" 'BEGIN {
    split("B KB MB GB TB", units)
    i = 1
    while (n >= 1024 && i < 5) { n /= 1024; i++ }
    printf "%.1f%s", n, units[i]
  }'
}

assert_safe_delete_path() {
  local path="$1"
  local label="$2"
  if [[ "$path" != /* ]]; then
    die "${label} 不是绝对路径：${path}"
  fi
  case "$path" in
    /|/root|/root/*|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/lib64|/lib64/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*|/tmp|/tmp/*|/var|/var/log|/var/log/*|/home|/opt|/srv)
      die "拒绝删除或覆盖 ${label}：${path}"
      ;;
  esac
  if [[ "${path#/}" != */* ]]; then
    die "拒绝使用过短的路径 ${path}"
  fi
}

init_drush() {
  local bin="$ROOT/vendor/bin/drush"
  if [[ ! -x "$bin" ]]; then
    log_err "找不到可执行的 ${bin}"
    return 1
  fi
  if [[ ! -f "$ROOT/web/index.php" ]]; then
    log_err "不像 Drupal 根目录，缺少 ${ROOT}/web/index.php"
    return 1
  fi
  DRUSH=("$bin" --root="$ROOT/web")
}

drush_stdout() {
  local out err rc
  out=$(mktemp)
  err=$(mktemp)
  set +e
  "${DRUSH[@]}" "$@" >"$out" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "drush $* 失败，退出码 ${rc}。"
    print_captured_error "$err" "$out"
    rm -f "$out" "$err"
    return "$rc"
  fi
  if [[ -s "$err" ]]; then
    redact_file "$err" >>"$LOG"
  fi
  cat "$out"
  rm -f "$out" "$err"
}

drush_run() {
  local out
  out=$(drush_stdout "$@") || return $?
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" | redact_stream | tee -a "$LOG"
  fi
}

sql_scalar() {
  local sql="$1"
  local out err rc value
  out=$(mktemp)
  err=$(mktemp)
  set +e
  "${DRUSH[@]}" sql:query "$sql" >"$out" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "SQL 查询失败：${sql}"
    print_captured_error "$err" "$out"
    rm -f "$out" "$err"
    return "$rc"
  fi
  value=$(awk 'NF && $1 ~ /^[0-9]+$/ { v = $1 } END { print v }' "$out")
  rm -f "$out" "$err"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    log_err "SQL 没有返回数字。查询：${sql}"
    return 1
  fi
  printf '%s' "$value"
}

count_files() {
  local dir="$1"
  local mode="$2"
  local out err rc
  if [[ ! -d "$dir" ]]; then
    printf '0'
    return 0
  fi
  out=$(mktemp)
  err=$(mktemp)
  set +e
  if [[ "$mode" == "public" ]]; then
    find "$dir" -type f \
      ! -path '*/php/*' \
      ! -path '*/css/*' \
      ! -path '*/js/*' \
      ! -path '*/styles/*' \
      -printf '.' >"$out" 2>"$err"
  else
    find "$dir" -type f -printf '.' >"$out" 2>"$err"
  fi
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "统计 ${dir} 中的文件失败。"
    print_captured_error "$err"
    rm -f "$out" "$err"
    return "$rc"
  fi
  wc -c <"$out" | tr -d '[:space:]'
  rm -f "$out" "$err"
}

private_should_count_extra() {
  local files_dir="$1"
  local abs="$2"
  local rel
  case "$abs" in
    "$files_dir"|"$files_dir"/*) ;;
    *) return 0 ;;
  esac
  rel="${abs#"$files_dir"/}"
  case "/${rel}/" in
    */php/*|*/css/*|*/js/*|*/styles/*) return 0 ;;
  esac
  return 1
}

count_site_files() {
  local root="$1"
  local private_abs="${2:-}"
  local files_dir public_count extra
  files_dir="$root/web/sites/default/files"
  public_count=$(count_files "$files_dir" public) || return 1
  extra=0
  if [[ -n "$private_abs" && -d "$private_abs" ]]; then
    if private_should_count_extra "$files_dir" "$private_abs"; then
      extra=$(count_files "$private_abs" all) || return 1
    fi
  fi
  printf '%s' "$((public_count + extra))"
}

load_db_prefix() {
  local raw prefix
  # shellcheck disable=SC2016
  raw=$(drush_stdout php:eval '$info = \Drupal\Core\Database\Database::getConnectionInfo("default"); $prefix = $info["prefix"] ?? ""; if (is_array($prefix)) { echo "PREFIX_COMPLEX\n"; } else { echo "PREFIX=", (string) $prefix, "\n"; }') || return 1
  if printf '%s\n' "$raw" | grep -q '^PREFIX_COMPLEX$'; then
    die "数据库前缀是按表区分的数组。脚本只接受字符串前缀，已中止，没有修改站点。"
  fi
  prefix=$(printf '%s\n' "$raw" | sed -n 's/^PREFIX=//p' | tail -n 1)
  if [[ ! "$prefix" =~ ^[A-Za-z0-9_]*$ ]]; then
    die "数据库前缀含有非法字符，已中止。"
  fi
  DB_PREFIX="$prefix"
  log_line "数据库表前缀：${DB_PREFIX:-（无）}"
}

structure_table_list() {
  local like_prefix sql raw list
  like_prefix=$(printf '%s' "$DB_PREFIX" | sed 's/\\/\\\\/g; s/%/\\%/g; s/_/\\_/g')
  sql="SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND (table_name = '${DB_PREFIX}cache' OR table_name LIKE '${like_prefix}cache\\_%' OR table_name = '${DB_PREFIX}sessions' OR table_name = '${DB_PREFIX}watchdog') ORDER BY table_name"
  raw=$(drush_stdout sql:query "$sql") || return 1
  list=$(printf '%s\n' "$raw" | awk 'NF && $1 ~ /^[A-Za-z0-9_]+$/ { printf "%s%s", (n ? "," : ""), $1; n = 1 }')
  if [[ -z "$list" ]]; then
    log_err "没有找到 cache、cache_*、sessions 或 watchdog。查询输出："
    printf '%s\n' "$raw" | redact_stream | tee -a "$LOG" >&2
    return 1
  fi
  printf '%s' "$list"
}

sha256_file() {
  local sum
  sum=$(sha256sum "$1" | awk 'NF { print $1; exit }')
  if [[ ! "$sum" =~ ^[0-9a-f]{64}$ ]]; then
    die "无法计算 sha256：${1}"
  fi
  printf '%s' "$sum"
}

manifest_value() {
  local key="$1"
  local file="$2"
  awk -F '=' -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

gzip_has_create_table() {
  local file="$1"
  local rc
  set +o pipefail
  set +e
  gzip -dc "$file" | grep -m 1 -q 'CREATE TABLE'
  rc=$?
  set -e
  set -o pipefail
  return "$rc"
}

validate_sql_gz() {
  local file="$1"
  local err
  err=$(mktemp)
  if ! gzip -t "$file" 2>"$err"; then
    log_err "不是有效的 gzip：${file}"
    print_captured_error "$err"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  if ! gzip_has_create_table "$file"; then
    die "压缩包里看不到 CREATE TABLE：${file}"
  fi
}

assert_bootstrap() {
  local raw value
  raw=$(drush_stdout status --field=bootstrap) || return 1
  value=$(printf '%s\n' "$raw" | tr -d '\r' | awk 'NF { print; exit }')
  if [[ "$value" != "Successful" ]]; then
    log_err "drush bootstrap 未成功。输出原文："
    printf '%s\n' "$raw" | redact_stream | tee -a "$LOG" >&2
    return 1
  fi
  BOOTSTRAP_VALUE="Successful"
  log_line "drush bootstrap 成功。"
}

read_settings_report() {
  local settings="$ROOT/web/sites/default/settings.php"
  local php
  if [[ ! -f "$settings" ]]; then
    return 1
  fi
  php=$(mktemp "$WORK/read-settings.XXXXXX.php")
  cat >"$php" <<'PHP'
<?php
$settings = [];
$databases = [];
$config = [];
$app_root = $argv[1];
$site_path = 'sites/default';
include $argv[2];
$db = $databases['default']['default']['database'] ?? '';
$prefix = $databases['default']['default']['prefix'] ?? '';
$private = $settings['file_private_path'] ?? '';
if (!is_string($db)) {
    $db = '';
}
echo "DB\t", $db, "\n";
if (is_array($prefix)) {
    echo "PREFIX_COMPLEX\n";
} else {
    echo "PREFIX\t", (string) $prefix, "\n";
}
echo "PRIVATE\t", (string) $private, "\n";
$patterns = $settings['trusted_host_patterns'] ?? [];
if (is_array($patterns)) {
    foreach ($patterns as $pattern) {
        if (is_string($pattern)) {
            echo "PATTERN\t", $pattern, "\n";
        }
    }
}
PHP
  php "$php" "$ROOT/web" "$settings"
}

settings_database_has_users_table() {
  local report db prefix err rc count table
  report=$(read_settings_report) || return 1
  if printf '%s\n' "$report" | grep -q '^PREFIX_COMPLEX$'; then
    log_err "settings.php 中的数据库前缀不是字符串。bootstrap 失败时无法安全判断站点是否已安装。"
    return 1
  fi
  db=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "DB" { print $2; exit }')
  prefix=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PREFIX" { print $2; exit }')
  if [[ ! "$db" =~ ^[A-Za-z0-9_]+$ || ! "$prefix" =~ ^[A-Za-z0-9_]*$ ]]; then
    log_err "无法从 settings.php 得到合法的数据库名。"
    return 1
  fi
  table="${prefix}users_field_data"
  err=$(mktemp)
  set +e
  count=$(mysql --protocol=socket --batch --skip-column-names --user=root -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db}' AND table_name='${table}'" 2>"$err")
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "无法查询 information_schema，不能判断站点是否已安装。"
    print_captured_error "$err"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  count=$(printf '%s' "$count" | tr -d '[:space:]')
  if [[ "$count" =~ ^[0-9]+$ && "$count" -ge 1 ]]; then
    return 0
  fi
  if [[ "$count" =~ ^[0-9]+$ ]]; then
    return 2
  fi
  log_err "information_schema 没有返回可识别的表数量。"
  return 1
}

disk_avail() {
  local path="$1"
  local avail
  if [[ ! -e "$path" ]]; then
    path=$(dirname "$path")
  fi
  avail=$(df -B1 --output=avail "$path" | awk 'NR == 2 { print $1 }')
  if [[ ! "$avail" =~ ^[0-9]+$ ]]; then
    die "无法读取磁盘剩余空间：${path}"
  fi
  printf '%s' "$avail"
}

assert_disk_space() {
  local bytes="$1"
  local need path avail
  need=$((bytes * 3))
  for path in /root "$ROOT"; do
    if [[ "$path" == "$ROOT" && ! -e "$ROOT" ]]; then
      path=$(dirname "$ROOT")
    fi
    avail=$(disk_avail "$path")
    log_line "磁盘检查：${path} 可用 ${avail} 字节，包大小 ${bytes} 字节，要求不少于 ${need} 字节。"
    if [[ "$avail" -lt "$need" ]]; then
      die "磁盘剩余空间不足。${path} 可用 ${avail} 字节，少于包大小的 3 倍（${need}）。"
    fi
  done
}

last_error_lines() {
  local file="$1"
  if [[ -f "$file" && -r "$file" ]]; then
    tail -n 400 "$file" | grep -E '\[error\]|\[crit\]|\[alert\]|\[emerg\]|PHP Fatal|PHP Parse|Uncaught|TypeError' | tail -n 3 || true
  fi
}

find_fpm_log() {
  local conf line path
  local -a confs=()
  shopt -s nullglob
  confs=(/etc/php/*/fpm/php-fpm.conf /etc/php/*/fpm/pool.d/www.conf)
  shopt -u nullglob
  for conf in "${confs[@]}"; do
    line=$(grep -E '^[[:space:]]*error_log[[:space:]]*=' "$conf" | tail -n 1 || true)
    path="${line#*=}"
    path="${path%%;*}"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    path="${path%\"}"
    path="${path#\"}"
    path="${path%\'}"
    path="${path#\'}"
    if [[ -n "$path" && -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  shopt -s nullglob
  confs=(/var/log/php*-fpm.log)
  shopt -u nullglob
  if [[ "${#confs[@]}" -gt 0 ]]; then
    printf '%s\n' "${confs[$((${#confs[@]} - 1))]}"
    return 0
  fi
  return 1
}

print_http_errors() {
  local nginx_lines fpm fpm_lines
  nginx_lines=$(last_error_lines /var/log/nginx/error.log || true)
  fpm=""
  fpm_lines=""
  if fpm=$(find_fpm_log); then
    fpm_lines=$(last_error_lines "$fpm" || true)
  else
    fpm="未找到"
  fi
  {
    printf '首页 5xx，最近错误如下：\n'
    printf 'nginx /var/log/nginx/error.log 最后 3 条错误：\n'
    if [[ -n "$nginx_lines" ]]; then
      printf '%s\n' "$nginx_lines"
    else
      printf '（无）\n'
    fi
    printf 'PHP-FPM %s 最后 3 条错误：\n' "$fpm"
    if [[ -n "$fpm_lines" ]]; then
      printf '%s\n' "$fpm_lines"
    else
      printf '（无）\n'
    fi
  } | redact_stream | tee -a "$LOG" >&2
}

http_code_for() {
  local host="$1"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 15 --max-time 60 http://127.0.0.1 -H "Host: ${host}" || true)
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
    code="000"
  fi
  printf '%s' "$code"
}

http_is_good() {
  [[ "$1" == "200" || "$1" =~ ^3[0-9][0-9]$ ]]
}

write_report() {
  local line tmp
  if [[ "$REPORT_WRITTEN" -eq 1 ]]; then
    return 0
  fi
  line="搬家验收：节点=${NEW_NODES}/${OLD_NODES}  用户=${NEW_USERS}/${OLD_USERS}  文件=${NEW_FILES}/${OLD_FILES}  bootstrap=${BOOTSTRAP_VALUE}  首页HTTP=${HTTP_CODE}  整体=${FINAL_OVERALL}"
  line=$(printf '%s' "$line" | redact_stream)
  printf '%s\n' "$line" | tee -a "$LOG"
  tmp=$(mktemp /root/xedc-migrate-report.XXXXXX)
  printf '%s\n' "$line" >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$REPORT"
  chmod 600 "$REPORT"
  REPORT_WRITTEN=1
}

backup_database() {
  local dest="$1"
  local err rc
  err=$(mktemp)
  log_line "备份数据库到 ${dest}"
  set +e
  "${DRUSH[@]}" sql:dump --gzip >"$dest" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "数据库备份失败，退出码 ${rc}。尚未删除现有数据。"
    print_captured_error "$err"
    rm -f "$dest" "$err"
    return 1
  fi
  if [[ -s "$err" ]]; then
    redact_file "$err" >>"$LOG"
  fi
  rm -f "$err"
  chmod 600 "$dest"
  validate_sql_gz "$dest"
}

backup_files_tree() {
  local dest="$1"
  local private_abs="${2:-}"
  local stage files_dir err rc
  files_dir="$ROOT/web/sites/default/files"
  if [[ ! -d "$files_dir" && -z "$private_abs" ]]; then
    warn "没有可备份的上传文件目录。"
    return 1
  fi
  stage="$WORK/file-backup"
  rm -rf "$stage"
  mkdir -p "$stage"
  if [[ -d "$files_dir" ]]; then
    ln -s "$files_dir" "$stage/files"
  else
    mkdir -p "$stage/files"
  fi
  if [[ -n "$private_abs" && -d "$private_abs" ]]; then
    ln -s "$private_abs" "$stage/private-files"
    printf '%s\n' "$private_abs" >"$stage/private-path.txt"
  fi
  err=$(mktemp)
  set +e
  tar -chzf "$dest" -C "$stage" . 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "备份上传文件失败。"
    print_captured_error "$err"
    rm -f "$dest" "$err"
    return 1
  fi
  rm -f "$err"
  chmod 600 "$dest"
  log_line "已备份上传文件到 ${dest}"
}

import_sql_gz() {
  local file="$1"
  local out err
  local -a rcs=()
  out=$(mktemp)
  err=$(mktemp)
  log_line "导入 SQL：${file}"
  set +e
  gunzip -c "$file" | "${DRUSH[@]}" sqlc >"$out" 2>"$err"
  rcs=("${PIPESTATUS[@]}")
  set -e
  if [[ "${rcs[0]}" -ne 0 || "${rcs[1]}" -ne 0 ]]; then
    log_err "导入 SQL 失败（gunzip=${rcs[0]}，drush sqlc=${rcs[1]}）。"
    print_captured_error "$err" "$out"
    rm -f "$out" "$err"
    return 1
  fi
  if [[ -s "$err" ]]; then
    redact_file "$err" >>"$LOG"
  fi
  if [[ -s "$out" ]]; then
    redact_file "$out" >>"$LOG"
  fi
  rm -f "$out" "$err"
}

enable_maintenance() {
  local which="$1"
  drush_run sset system.maintenance_mode 1 || return 1
  if [[ "$which" == "import" ]]; then
    IMPORT_MAINT=1
  else
    ROLLBACK_MAINT=1
  fi
  log_line "已开启维护模式。"
}

disable_maintenance() {
  local which="$1"
  drush_run sset system.maintenance_mode 0 || return 1
  if [[ "$which" == "import" ]]; then
    IMPORT_MAINT=0
  else
    ROLLBACK_MAINT=0
  fi
  log_line "已关闭维护模式。"
}

drop_tables() {
  log_line "删除现有数据表：drush sql:drop -y"
  drush_run sql:drop -y
}

replace_public_files_from_dir() {
  local source_files="$1"
  local files_dir="$ROOT/web/sites/default/files"
  if [[ "$files_dir" != "$ROOT/web/sites/default/files" ]]; then
    die "公共文件路径异常：${files_dir}"
  fi
  assert_safe_delete_path "$files_dir" "公共文件目录"
  rm -rf -- "$files_dir"
  mkdir -p "$ROOT/web/sites/default"
  mv "$source_files" "$files_dir"
}

chown_web_files() {
  local private_abs="${1:-}"
  local files_dir="$ROOT/web/sites/default/files"
  if ! id www-data >/dev/null 2>&1; then
    die "系统里没有 www-data 用户。"
  fi
  if [[ -d "$files_dir" ]]; then
    chown -R www-data:www-data "$files_dir" || die "无法把 ${files_dir} 交给 www-data。"
  fi
  if [[ -n "$private_abs" && -d "$private_abs" ]]; then
    assert_safe_delete_path "$private_abs" "私有文件目录"
    chown -R www-data:www-data "$private_abs" || die "无法把 ${private_abs} 交给 www-data。"
  fi
  log_line "已将文件目录的所有者设为 www-data:www-data。"
}

validate_relative_tar() {
  local list="$1"
  local kind="$2"
  local entry norm
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    norm="${entry#./}"
    case "$norm" in
      /*|*..*)
        die "${kind} 含有不安全路径：${entry}"
        ;;
    esac
    if [[ "$kind" == "公共文件" ]]; then
      case "$norm" in
        ''|files|files/*) ;;
        *) die "公共文件包含有意外路径：${entry}" ;;
      esac
    fi
  done <"$list"
}

extract_checked_tar() {
  local archive="$1"
  local dest="$2"
  local kind="$3"
  local list err rc
  list=$(mktemp)
  err=$(mktemp)
  if ! tar -tzf "$archive" >"$list" 2>"$err"; then
    log_err "无法列出 ${kind}：${archive}"
    print_captured_error "$err"
    rm -f "$list" "$err"
    return 1
  fi
  rm -f "$err"
  validate_relative_tar "$list" "$kind"
  rm -f "$list"
  mkdir -p "$dest"
  err=$(mktemp)
  set +e
  tar -xzf "$archive" -C "$dest" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "解压 ${kind} 失败。"
    print_captured_error "$err"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
}

# --- export 步骤 1：定位根目录并确认 drush bootstrap ---
export_assert_drupal() {
  require_cmd php tar gzip sha256sum find df awk sed git stat flock
  if [[ ! -d "$ROOT" ]]; then
    die "Drupal 根目录不存在：${ROOT}"
  fi
  init_drush || die "drush 不可用。"
  assert_bootstrap || die "drush bootstrap 未成功，已停止。没有修改站点。"
  load_db_prefix || die "无法读取数据库前缀。没有修改站点。"
}

# --- export 步骤 2：检查未提交改动和未推送到远端跟踪分支的提交 ---
export_warn_unpushed() {
  local dirty upstream unpushed
  if [[ ! -d "$ROOT/.git" ]]; then
    warn "新服务器只能拉到 GitHub 上的代码。当前目录不是 Git 仓库。"
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      die "未加 --yes，已停止。没有修改站点。"
    fi
    log_line "已加 --yes，在非 Git 目录上继续导出。"
    return 0
  fi
  dirty=$(git -C "$ROOT" status --porcelain || true)
  unpushed=""
  if upstream=$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    unpushed=$(git -C "$ROOT" log --oneline "${upstream}..HEAD" || true)
  elif git -C "$ROOT" rev-parse --verify origin/main >/dev/null 2>&1; then
    unpushed=$(git -C "$ROOT" log --oneline "origin/main..HEAD" || true)
  else
    unpushed="（没有上游分支，也没有 origin/main，无法确认本地提交是否已在 GitHub。比较时没有更新远端跟踪分支。）"
  fi
  if [[ -n "$dirty" || -n "$unpushed" ]]; then
    warn "新服务器只能拉到 GitHub 上的代码。"
    if [[ -n "$dirty" ]]; then
      printf '未提交的改动：\n%s\n' "$dirty" | tee -a "$LOG" >&2
    fi
    if [[ -n "$unpushed" ]]; then
      printf '尚未出现在远端跟踪分支上的提交：\n%s\n' "$unpushed" | tee -a "$LOG" >&2
    fi
    warn "以上比较使用本机已有的远端跟踪分支，没有访问网络。"
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      die "确认这些改动不会进新服务器后，请追加 --yes。没有修改站点。"
    fi
    log_line "已加 --yes，在工作区不干净或有未同步提交时继续导出。"
  else
    log_line "工作区干净，相对远端跟踪分支没有未同步的提交。"
  fi
}

# --- export 步骤 3：仅在 --maintenance 时打开维护模式 ---
export_enable_maintenance() {
  local err rc
  if [[ "$MAINTENANCE" -ne 1 ]]; then
    log_line "未加 --maintenance，不改动维护模式。"
    return 0
  fi
  err=$(mktemp)
  set +e
  "${DRUSH[@]}" sset system.maintenance_mode 1 >"$err" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "无法打开维护模式。"
    print_captured_error "$err"
    rm -f "$err"
    die "已停止。没有导出，也没有把维护模式写成 1。"
  fi
  rm -f "$err"
  EXPORT_MAINT=1
  log_line "已打开维护模式。脚本结束或异常退出时会写回 0。"
}

# --- export 步骤 4：导出数据库，cache / cache_* / sessions / watchdog 只保留结构 ---
export_database() {
  local list dest err rc
  dest="$WORK/payload/database.sql.gz"
  list=$(structure_table_list) || die "无法确定只导出结构的表。没有修改站点。"
  log_line "这些表只导出结构：${list}"
  err=$(mktemp)
  set +e
  "${DRUSH[@]}" sql:dump --gzip --structure-tables-list="$list" >"$dest" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "drush sql:dump 失败，退出码 ${rc}。"
    print_captured_error "$err"
    rm -f "$dest" "$err"
    die "数据库导出失败。没有修改数据库内容。"
  fi
  if [[ -s "$err" ]]; then
    redact_file "$err" >>"$LOG"
  fi
  rm -f "$err"
  chmod 600 "$dest"
  validate_sql_gz "$dest" || die "数据库导出文件无效。没有修改数据库内容。"
  log_line "数据库导出完成：${dest}"
}

pack_public_files() {
  local files_dir dest err rc stage
  files_dir="$ROOT/web/sites/default/files"
  dest="$WORK/payload/public-files.tgz"
  err=$(mktemp)
  if [[ -d "$files_dir" ]]; then
    set +e
    tar -C "$ROOT/web/sites/default" \
      --exclude=php --exclude=css --exclude=js --exclude=styles \
      -czf "$dest" files 2>"$err"
    rc=$?
    set -e
  else
    warn "没有 ${files_dir}，公共文件包将是空的 files 目录。"
    stage="$WORK/empty-files"
    mkdir -p "$stage/files"
    set +e
    tar -C "$stage" -czf "$dest" files 2>"$err"
    rc=$?
    set -e
  fi
  if [[ "$rc" -ne 0 ]]; then
    log_err "打包公共文件失败。"
    print_captured_error "$err"
    rm -f "$err"
    die "没有修改上传文件。"
  fi
  rm -f "$err"
  chmod 600 "$dest"
}

resolve_existing_dir() {
  local raw="$1"
  local candidate
  if [[ -z "$raw" ]]; then
    return 0
  fi
  if [[ "$raw" == /* ]]; then
    if [[ -d "$raw" ]]; then
      readlink -f "$raw"
    fi
    return 0
  fi
  candidate=$(readlink -m "$ROOT/web/$raw")
  if [[ -d "$candidate" ]]; then
    readlink -f "$candidate"
    return 0
  fi
  candidate=$(readlink -m "$ROOT/$raw")
  if [[ -d "$candidate" ]]; then
    readlink -f "$candidate"
  fi
}

# --- export 步骤 5：打包公共文件和私有文件 ---
export_pack_files() {
  local raw abs dest err rc
  pack_public_files
  raw=$(drush_stdout php:eval 'echo "PRIVATE_PATH=", (string) (\Drupal\Core\Site\Settings::get("file_private_path") ?? ""), "\n";') || die "无法用 drush php:eval 读取 file_private_path。"
  raw=$(printf '%s\n' "$raw" | sed -n 's/^PRIVATE_PATH=//p' | tail -n 1 | tr -d '\r')
  printf '%s\n' "$raw" >"$WORK/private-raw.txt"
  printf '\n' >"$WORK/private-abs.txt"
  if [[ -z "$raw" ]]; then
    log_line "file_private_path 为空，不打包私有文件。"
    return 0
  fi
  case "$raw" in
    *$'\n'*|*=*)
      die "file_private_path 含有换行或等号，无法写入 manifest。"
      ;;
  esac
  abs=$(resolve_existing_dir "$raw" || true)
  if [[ -z "$abs" || ! -d "$abs" ]]; then
    warn "file_private_path 为 ${raw}，但目录不存在，本次不打包私有文件。"
    return 0
  fi
  printf '%s\n' "$abs" >"$WORK/private-abs.txt"
  dest="$WORK/payload/private-files.tgz"
  err=$(mktemp)
  set +e
  tar -C "$abs" -czf "$dest" . 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "打包私有文件失败：${abs}"
    print_captured_error "$err"
    rm -f "$err"
    die "没有修改私有文件。"
  fi
  rm -f "$err"
  chmod 600 "$dest"
  log_line "已打包私有文件。原路径 ${raw}，绝对路径 ${abs}。"
}

host_of_url() {
  # shellcheck disable=SC2016
  php -r '
    $raw = trim((string) ($argv[1] ?? ""));
    if ($raw === "") { exit(0); }
    if (!str_contains($raw, "://")) { $raw = "http://" . $raw; }
    $parts = parse_url($raw);
    echo $parts["host"] ?? "";
  ' "$1"
}

# --- export 步骤 6：写 manifest.txt ---
export_write_manifest() {
  local now drupal_version php_version mariadb_version git_commit base old_domain
  local node_rows user_rows file_rows private_raw private_abs db_hash pub_hash priv_hash
  now=$(date '+%F %T %z')
  drupal_version=$(drush_stdout status --field=drupal-version) || die "无法读取 Drupal 版本。"
  drupal_version=$(printf '%s\n' "$drupal_version" | awk 'NF { print; exit }')
  php_version=$(php -r 'echo PHP_VERSION;')
  mariadb_version=$(sql_scalar "SELECT VERSION()") || die "无法读取 MariaDB 版本。"
  if [[ -d "$ROOT/.git" ]]; then
    git_commit=$(git -C "$ROOT" rev-parse HEAD)
  else
    git_commit="无"
  fi
  if base=$(drush_stdout config:get simple_sitemap.settings base_url --format=string); then
    base=$(printf '%s\n' "$base" | awk 'NF { print; exit }' | tr -d '\r"'"'"'')
  else
    base=""
    warn "无法读取 simple_sitemap.settings base_url，旧站域名改用主机名。"
  fi
  old_domain=$(host_of_url "$base")
  if [[ -z "$old_domain" ]]; then
    old_domain=$(hostname -f 2>/dev/null || hostname)
    base="${base:-$old_domain}"
  fi
  node_rows=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}node_field_data\`") || die "无法统计 node_field_data。"
  user_rows=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}users\`") || die "无法统计 users。"
  private_raw=$(tr -d '\r' <"$WORK/private-raw.txt" || true)
  private_abs=$(tr -d '\r' <"$WORK/private-abs.txt" || true)
  if [[ -n "$private_abs" && ! -d "$private_abs" ]]; then
    private_abs=""
  fi
  file_rows=$(count_site_files "$ROOT" "$private_abs") || die "无法统计上传文件。"
  db_hash=$(sha256_file "$WORK/payload/database.sql.gz")
  pub_hash=$(sha256_file "$WORK/payload/public-files.tgz")
  priv_hash=""
  if [[ -f "$WORK/payload/private-files.tgz" ]]; then
    priv_hash=$(sha256_file "$WORK/payload/private-files.tgz")
  fi
  {
    printf '%s\n' '# xedc-migrate manifest v1'
    printf '时间=%s\n' "$now"
    printf 'Drupal版本=%s\n' "$drupal_version"
    printf 'PHP版本=%s\n' "$php_version"
    printf 'MariaDB版本=%s\n' "$mariadb_version"
    printf 'git提交=%s\n' "$git_commit"
    printf '旧站域名=%s\n' "$old_domain"
    printf '旧站base_url=%s\n' "$base"
    printf 'node_field_data行数=%s\n' "$node_rows"
    printf 'users行数=%s\n' "$user_rows"
    printf 'files文件数=%s\n' "$file_rows"
    printf '私有文件路径=%s\n' "$private_raw"
    printf '私有文件绝对路径=%s\n' "$private_abs"
    printf 'sha256 database.sql.gz %s\n' "$db_hash"
    printf 'sha256 public-files.tgz %s\n' "$pub_hash"
    if [[ -n "$priv_hash" ]]; then
      printf 'sha256 private-files.tgz %s\n' "$priv_hash"
    fi
  } >"$WORK/payload/manifest.txt"
  chmod 600 "$WORK/payload/manifest.txt"
  log_line "已生成 manifest。"
  tee -a "$LOG" <"$WORK/payload/manifest.txt"
}

# --- export 步骤 7：打成单个权限 600 的 tgz，并提示传输和保密 ---
export_write_package() {
  local ts final bytes err rc
  ts=$(date '+%Y%m%d%H%M%S')
  if [[ ! -d "$OUT" ]]; then
    mkdir -p "$OUT"
    chmod 700 "$OUT"
  fi
  final="$OUT/xedc-migrate-${ts}.tgz"
  if [[ -e "$final" ]]; then
    final="$OUT/xedc-migrate-${ts}-$$.tgz"
  fi
  err=$(mktemp)
  set +e
  tar -C "$WORK/payload" -czf "$WORK/package.tgz" . 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "打包最终归档失败。"
    print_captured_error "$err"
    rm -f "$err"
    die "没有留下半成品包。"
  fi
  rm -f "$err"
  mv "$WORK/package.tgz" "$final"
  chmod 600 "$final"
  bytes=$(stat -c '%s' "$final")
  log_line "包路径：${final}"
  printf '包路径：%s\n包大小：%s 字节（%s）\n权限：600\n' "$final" "$bytes" "$(human_size "$bytes")" | tee -a "$LOG"
  cat <<EOF | tee -a "$LOG"

用 scp 把包拷到新服务器，例如：
  scp ${final} root@新服务器:/root/

包含用户邮箱和密码哈希，不要放进 GitHub，用完在两边删除。
EOF
}

export_main() {
  export_assert_drupal
  export_warn_unpushed
  export_enable_maintenance
  mkdir -p "$WORK/payload"
  export_database
  export_pack_files
  export_write_manifest
  export_write_package
  restore_export_maintenance || die "包已写好，但维护模式未能恢复为 0。请立刻检查站点。"
  log_line "export 完成。没有修改数据库内容、上传文件或 settings.php。"
}

# --- import 步骤 1：校验包、打印 manifest、检查磁盘 ---
import_verify_pack() {
  local bytes list err entry norm manifest name sum actual
  require_cmd php tar gzip sha256sum find df awk sed curl stat flock
  bytes=$(stat -c '%s' "$PACK")
  if [[ "$bytes" -le 0 ]]; then
    die "包是空文件：${PACK}"
  fi
  assert_disk_space "$bytes"
  list=$(mktemp)
  err=$(mktemp)
  if ! tar -tzf "$PACK" >"$list" 2>"$err"; then
    log_err "无法读取包 ${PACK}"
    print_captured_error "$err"
    rm -f "$list" "$err"
    die "包没有解压，站点没有改动。"
  fi
  rm -f "$err"
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    norm="${entry#./}"
    norm="${norm%/}"
    case "$norm" in
      ''|manifest.txt|database.sql.gz|public-files.tgz|private-files.tgz) ;;
      *)
        die "包内有意外文件 ${entry}，已中止。站点没有改动。"
        ;;
    esac
  done <"$list"
  rm -f "$list"
  mkdir -p "$WORK/payload"
  err=$(mktemp)
  if ! tar -xzf "$PACK" -C "$WORK/payload" 2>"$err"; then
    log_err "解压包失败。"
    print_captured_error "$err"
    rm -f "$err"
    die "站点没有改动。"
  fi
  rm -f "$err"
  manifest="$WORK/payload/manifest.txt"
  if [[ ! -f "$manifest" ]] || ! grep -q '^# xedc-migrate manifest v1$' "$manifest"; then
    die "包内没有可识别的 manifest.txt。站点没有改动。"
  fi
  if [[ ! -f "$WORK/payload/database.sql.gz" || ! -f "$WORK/payload/public-files.tgz" ]]; then
    die "包内缺少 database.sql.gz 或 public-files.tgz。站点没有改动。"
  fi
  while read -r kind name sum; do
    [[ "$kind" == "sha256" ]] || continue
    case "$name" in
      database.sql.gz|public-files.tgz|private-files.tgz) ;;
      *) die "manifest 记录了意外文件 ${name}。" ;;
    esac
    if [[ ! -f "$WORK/payload/$name" ]]; then
      die "manifest 记录了 ${name}，但包内没有这个文件。"
    fi
    if [[ ! "$sum" =~ ^[0-9a-f]{64}$ ]]; then
      die "manifest 中 ${name} 的 sha256 无效。"
    fi
    actual=$(sha256_file "$WORK/payload/$name")
    if [[ "$actual" != "$sum" ]]; then
      die "sha256 不一致：${name} 期望 ${sum} 实际 ${actual}。站点没有改动。"
    fi
    log_line "sha256 一致：${name}"
  done <"$manifest"
  for name in database.sql.gz public-files.tgz; do
    if ! grep -q "^sha256 ${name} " "$manifest"; then
      die "manifest 没有 ${name} 的 sha256。"
    fi
  done
  if [[ -f "$WORK/payload/private-files.tgz" ]] && ! grep -q '^sha256 private-files.tgz ' "$manifest"; then
    die "包内有 private-files.tgz，但 manifest 没有它的 sha256。"
  fi
  log_line "manifest 如下："
  tee -a "$LOG" <"$manifest"
  validate_sql_gz "$WORK/payload/database.sql.gz" || die "数据库包无效。站点没有改动。"
  import_stage_archives
}

import_stage_archives() {
  local manifest raw abs dest
  extract_checked_tar "$WORK/payload/public-files.tgz" "$WORK/public-unpack" "公共文件" || die "公共文件没有通过检查。站点没有改动。"
  if [[ ! -d "$WORK/public-unpack/files" ]]; then
    die "公共文件包里没有 files 目录。站点没有改动。"
  fi
  manifest="$WORK/payload/manifest.txt"
  raw=$(manifest_value "私有文件路径" "$manifest")
  abs=$(manifest_value "私有文件绝对路径" "$manifest")
  if [[ ! -f "$WORK/payload/private-files.tgz" ]]; then
    if [[ -n "$raw" ]]; then
      warn "manifest 记录了私有文件路径 ${raw}，但包内没有 private-files.tgz。"
    fi
    printf '\n' >"$WORK/private-dest.txt"
    return 0
  fi
  if [[ -n "$abs" ]]; then
    dest="$abs"
  elif [[ "$raw" == /* ]]; then
    dest="$raw"
  elif [[ -n "$raw" ]]; then
    dest=$(readlink -m "$ROOT/web/$raw")
  else
    die "有 private-files.tgz，但 manifest 没有私有文件路径。站点没有改动。"
  fi
  assert_safe_delete_path "$dest" "私有文件目录"
  extract_checked_tar "$WORK/payload/private-files.tgz" "$WORK/private-unpack" "私有文件" || die "私有文件没有通过检查。站点没有改动。"
  printf '%s\n' "$dest" >"$WORK/private-dest.txt"
  log_line "私有文件将解压到 ${dest}。覆盖前还会再备份现有文件。"
}

# --- import 步骤 2：站点不存在或未安装时运行 install-restore.sh ---
import_ensure_codebase() {
  local needs=0 installer err installer_rc status_line users_rc table_count
  if [[ ! -d "$ROOT" || ! -x "$ROOT/vendor/bin/drush" || ! -f "$ROOT/web/sites/default/settings.php" || ! -f "$ROOT/web/index.php" ]]; then
    needs=1
  else
    if init_drush && assert_bootstrap; then
      load_db_prefix || die "已有站点但读不到数据库前缀，已中止。没有覆盖数据。"
      table_count=$(sql_scalar "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '${DB_PREFIX}users_field_data'") || die "无法确认 users_field_data 是否存在。没有运行 install-restore.sh，也没有覆盖数据。"
      if [[ "$table_count" -ge 1 ]]; then
        needs=0
      else
        needs=1
      fi
    else
      users_rc=0
      settings_database_has_users_table || users_rc=$?
      if [[ "$users_rc" -eq 0 ]]; then
        die "目标目录里已有 users_field_data，但 drush bootstrap 失败。为避免移走现有代码，没有运行 install-restore.sh，也没有覆盖数据。"
      elif [[ "$users_rc" -eq 2 ]]; then
        needs=1
      else
        die "bootstrap 失败，且无法确认数据库里是否已有站点。没有运行 install-restore.sh，也没有覆盖数据。"
      fi
    fi
  fi
  if [[ "$needs" -eq 0 ]]; then
    log_line "目标站点已安装，不运行 install-restore.sh。"
    return 0
  fi
  log_line "根目录不存在或站点未安装，将下载并运行 install-restore.sh。它的最终状态即使是失败或部分成功，也会继续用备份包覆盖数据库。"
  if [[ -e "$ROOT" ]]; then
    warn "install-restore.sh 在目录已存在且带 --yes 时，会先把 ${ROOT} 整目录改名备份，再克隆 GitHub 上的代码。"
  fi
  installer="$WORK/install-restore.sh"
  err=$(mktemp)
  if ! curl -fsSL -o "$installer" "https://raw.githubusercontent.com/xxedc/drupal/main/install-restore.sh" 2>"$err"; then
    log_err "下载 install-restore.sh 失败。"
    print_captured_error "$err"
    rm -f "$err"
    die "没有得到可安装的代码。"
  fi
  rm -f "$err"
  chmod 700 "$installer"
  : >"$WORK/installer.out"
  log_line "运行 install-restore.sh，域名 ${DOMAIN}，目录 ${ROOT}。"
  set +e
  bash "$installer" "$DOMAIN" --yes --app-root "$ROOT" 2>&1 | redact_stream | tee -a "$LOG" "$WORK/installer.out"
  installer_rc=${PIPESTATUS[0]}
  set -e
  status_line=$(grep -E '整体[=：]' "$WORK/installer.out" | tail -n 1 || true)
  log_line "install-restore.sh 退出码 ${installer_rc}。状态行：${status_line:-未找到}。失败或部分成功不在这里中止。"
  if ! init_drush; then
    die "install-restore.sh 结束后仍然没有可用的 drush。退出码 ${installer_rc}。完整输出已写在日志里，终端上也已经打印过错误原文。"
  fi
  if ! assert_bootstrap; then
    die "install-restore.sh 结束后 bootstrap 仍未成功。退出码 ${installer_rc}。状态行：${status_line:-未找到}。没有导入备份包。"
  fi
  load_db_prefix || die "安装后无法读取数据库前缀，已中止。没有导入备份包。"
  log_line "drush 可用且 bootstrap 成功，继续用备份包覆盖数据库。"
}

# --- import 步骤 3：安全闸，并在覆盖前自动备份 ---
import_safety_gate() {
  local nodes extra
  nodes=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}node_field_data\`") || die "无法统计目标库 node_field_data。没有覆盖数据。"
  extra=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}users\` WHERE uid > 1") || die "无法统计目标库 uid>1 的用户。没有覆盖数据。"
  log_line "目标库 node_field_data=${nodes}，uid>1 的用户=${extra}。"
  if [[ "$nodes" -gt 0 || "$extra" -gt 0 ]]; then
    if [[ "$FORCE" -ne 1 || "$ASSUME_YES" -ne 1 ]]; then
      die "目标库已有真实内容（node_field_data=${nodes}，uid>1 的用户=${extra}）。覆盖必须同时传入 --force 和 --yes。没有备份，也没有覆盖。"
    fi
    log_line "已同时提供 --force 和 --yes，将在备份后覆盖现有内容。"
  else
    log_line "目标库没有节点，也没有 uid>1 的用户。仍会在覆盖前备份。"
  fi
}

current_private_dir() {
  local report raw
  if [[ ! -f "$ROOT/web/sites/default/settings.php" ]]; then
    return 0
  fi
  report=$(read_settings_report || true)
  raw=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PRIVATE" { print $2; exit }')
  if [[ -z "$raw" ]]; then
    return 0
  fi
  if [[ "$raw" != /* ]]; then
    raw=$(resolve_existing_dir "$raw" || true)
  fi
  if [[ -n "$raw" && -d "$raw" ]]; then
    printf '%s' "$raw"
  fi
}

import_backup_existing() {
  local ts private_abs
  ts=$(date '+%Y%m%d%H%M%S')
  PREMIGRATE_SQL="/root/xedc-premigrate-${ts}.sql.gz"
  PREMIGRATE_FILES="/root/xedc-premigrate-${ts}-files.tgz"
  private_abs=$(current_private_dir || true)
  backup_database "$PREMIGRATE_SQL" || die "覆盖前数据库备份失败。没有删除现有数据。"
  if ! backup_files_tree "$PREMIGRATE_FILES" "$private_abs"; then
    die "覆盖前文件备份失败。数据库备份留在 ${PREMIGRATE_SQL}。没有删除现有数据。"
  fi
  log_line "覆盖前备份：数据库 ${PREMIGRATE_SQL}"
  log_line "覆盖前备份：文件 ${PREMIGRATE_FILES}"
  log_line "回滚命令：${0} rollback --backup ${PREMIGRATE_SQL} --root ${ROOT} --yes"
  printf '\n覆盖前备份：\n数据库：%s\n文件：%s\n回滚命令：\n  %s rollback --backup %s --root %s --yes\n\n' \
    "$PREMIGRATE_SQL" "$PREMIGRATE_FILES" "$0" "$PREMIGRATE_SQL" "$ROOT" | tee -a "$LOG"
}

# --- import 步骤 4：维护模式、替换数据库和文件、更新、清缓存 ---
import_enable_maintenance() {
  enable_maintenance import || die "无法打开维护模式。现有备份仍在 ${PREMIGRATE_SQL}。尚未删除数据表。"
}

import_database() {
  drop_tables || die "drush sql:drop 失败。可使用回滚命令恢复覆盖前备份。"
  import_sql_gz "$WORK/payload/database.sql.gz" || die "数据库导入失败。可使用回滚命令恢复覆盖前备份：${PREMIGRATE_SQL}"
}

import_extract_files() {
  if [[ ! -d "$WORK/public-unpack/files" ]]; then
    die "公共文件还没有解压到临时目录。数据库已经导入，可使用回滚命令。"
  fi
  replace_public_files_from_dir "$WORK/public-unpack/files"
  log_line "已替换 ${ROOT}/web/sites/default/files。"
}

import_extract_private() {
  local dest files_dir
  dest=$(tr -d '\r' <"$WORK/private-dest.txt" || true)
  if [[ -z "$dest" ]]; then
    log_line "没有需要放入站点的私有文件。"
    return 0
  fi
  if [[ ! -d "$WORK/private-unpack" ]]; then
    die "私有文件还没有解压到临时目录。数据库已经导入，可使用回滚命令。"
  fi
  files_dir="$ROOT/web/sites/default/files"
  if [[ -L "$dest" ]]; then
    die "私有文件路径是符号链接，拒绝删除其内容：${dest}"
  fi
  mkdir -p "$dest"
  case "$dest" in
    "$files_dir"|"$files_dir"/*)
      log_line "私有路径位于公共 files 之内，解压覆盖，不先删除整个公共目录。"
      ;;
    *)
      find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      ;;
  esac
  tar -C "$WORK/private-unpack" -cf - . | tar -C "$dest" -xf -
  log_line "私有文件已解压到 ${dest}。"
}

import_confirm_private_path() {
  local dest report settings_private resolved_settings resolved_dest
  dest=$(tr -d '\r' <"$WORK/private-dest.txt" || true)
  if [[ -z "$dest" ]]; then
    log_line "没有私有文件路径需要和 settings.php 对照。"
    return 0
  fi
  report=$(read_settings_report) || die "无法读取 settings.php 中的 file_private_path。"
  settings_private=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PRIVATE" { print $2; exit }')
  if [[ -z "$settings_private" ]]; then
    warn "settings.php 没有 file_private_path，包内私有文件在 ${dest}。脚本不会修改 settings.php。"
    return 0
  fi
  if [[ "$settings_private" == /* ]]; then
    resolved_settings=$(readlink -m "$settings_private")
  else
    resolved_settings=$(readlink -m "$ROOT/web/$settings_private")
  fi
  resolved_dest=$(readlink -m "$dest")
  if [[ "$settings_private" == "$dest" || "$resolved_settings" == "$resolved_dest" ]]; then
    log_line "settings.php 的 file_private_path 与解压路径一致：${resolved_dest}"
  else
    warn "settings.php 的 file_private_path（${settings_private}，解析为 ${resolved_settings}）与包内路径（${resolved_dest}）不一致。脚本不会修改 settings.php。"
  fi
}

import_chown_files() {
  local dest
  dest=$(tr -d '\r' <"$WORK/private-dest.txt" || true)
  chown_web_files "$dest"
}

import_update_database() {
  if ! drush_run updb -y; then
    STEP_FAILED=1
    warn "drush updb -y 失败。继续做缓存重建和验收，整体不会记为成功。"
  fi
}

import_rebuild_cache() {
  if ! drush_run cr; then
    STEP_FAILED=1
    warn "drush cr 失败。继续验收，整体不会记为成功。"
  fi
}

import_disable_maintenance() {
  if ! disable_maintenance import; then
    STEP_FAILED=1
    warn "无法关闭维护模式。首页检查可能得到 503。脚本不会假装已经关闭。"
  fi
}

# --- import 步骤 5：域名不同时只提示，不改配置 ---
import_warn_domain() {
  local manifest old_domain old_lc new_lc base report pattern matched php
  manifest="$WORK/payload/manifest.txt"
  old_domain=$(manifest_value "旧站域名" "$manifest")
  old_lc=$(printf '%s' "$old_domain" | tr '[:upper:]' '[:lower:]')
  new_lc=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  report=$(read_settings_report || true)
  matched=0
  if [[ -z "$report" ]]; then
    warn "无法读取 settings.php 的 trusted_host_patterns。"
  else
    if ! printf '%s\n' "$report" | grep -q $'^PATTERN\t'; then
      warn "settings.php 的 trusted_host_patterns 为空。脚本不会修改 settings.php。"
    fi
    while IFS=$'\t' read -r key pattern; do
      [[ "$key" == "PATTERN" ]] || continue
      printf 'trusted_host_patterns：%s\n' "$pattern" | tee -a "$LOG"
      # shellcheck disable=SC2016
      if php -r '
        $pattern = $argv[1];
        $domain = $argv[2];
        $regex = "\x01" . $pattern . "\x01";
        $result = @preg_match($regex, $domain);
        exit($result === 1 ? 0 : 1);
      ' "$pattern" "$DOMAIN"; then
        matched=1
      fi
    done <<<"$report"
    if [[ "$matched" -ne 1 ]]; then
      warn "settings.php 的 trusted_host_patterns 没有包含 ${DOMAIN}。脚本不会修改 settings.php。"
    else
      log_line "trusted_host_patterns 包含 ${DOMAIN}。"
    fi
  fi
  if [[ -n "$old_lc" && "$old_lc" != "$new_lc" ]]; then
    if base=$(drush_stdout config:get simple_sitemap.settings base_url --format=string); then
      base=$(printf '%s\n' "$base" | awk 'NF { print; exit }')
      log_line "simple_sitemap.settings base_url=${base}"
      if printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | grep -F -q "$old_lc"; then
        warn "simple_sitemap.settings base_url 仍包含旧域名 ${old_domain}。脚本不会自动修改。"
      fi
    else
      warn "无法读取 simple_sitemap.settings base_url。"
    fi
    php=$(mktemp "$WORK/scan-host.XXXXXX.php")
    cat >"$php" <<'PHP'
$old = getenv("OLD_HOST");
$new = getenv("NEW_HOST");
if (!is_string($old) || $old === "" || strcasecmp($old, (string) $new) === 0) {
  return;
}
$shown = 0;
foreach (\Drupal::configFactory()->listAll() as $name) {
  $data = \Drupal::config($name)->getRawData();
  $keys = [];
  $walk = function ($value, $key) use (&$walk, &$keys, $old) {
    if (is_array($value)) {
      foreach ($value as $child_key => $child) {
        $next = $key === "" ? (string) $child_key : $key . "." . $child_key;
        $walk($child, $next);
      }
      return;
    }
    if (!is_string($value) || !str_contains($value, $old)) {
      return;
    }
    if (preg_match("/pass|secret|token|salt|credential|api_key/i", (string) $key)) {
      return;
    }
    $keys[] = $key === "" ? "(root)" : $key;
  };
  $walk($data, "");
  foreach ($keys as $key) {
    echo $name, " ", $key, "\n";
    $shown++;
    if ($shown >= 50) {
      echo "（还有更多包含旧域名的配置，已停止列举）\n";
      return;
    }
  }
}
PHP
    log_line "仍包含旧域名 ${old_domain} 的配置名（不打印配置值）："
    if ! OLD_HOST="$old_domain" NEW_HOST="$DOMAIN" "${DRUSH[@]}" php:script - --format=string <"$php" | redact_stream | tee -a "$LOG"; then
      warn "扫描旧域名时出错。上面是错误原文。脚本没有修改这些配置。"
    fi
  else
    log_line "新旧域名相同（${DOMAIN}），不提示域名替换。"
  fi
}

compare_count() {
  local label="$1"
  local newv="$2"
  local oldv="$3"
  local mark="不一致"
  if [[ "$newv" == "$oldv" && "$newv" =~ ^[0-9]+$ ]]; then
    mark="一致"
  fi
  printf '%s：新=%s 旧=%s %s\n' "$label" "$newv" "$oldv" "$mark" | tee -a "$LOG"
}

# --- import 步骤 6：对照数量、bootstrap 和首页 ---
import_acceptance() {
  local manifest private_abs
  manifest="$WORK/payload/manifest.txt"
  OLD_NODES=$(manifest_value "node_field_data行数" "$manifest")
  OLD_USERS=$(manifest_value "users行数" "$manifest")
  OLD_FILES=$(manifest_value "files文件数" "$manifest")
  private_abs=$(tr -d '\r' <"$WORK/private-dest.txt" || true)
  NEW_NODES=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}node_field_data\`" || true)
  NEW_USERS=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}users\`" || true)
  NEW_FILES=$(count_site_files "$ROOT" "$private_abs" || true)
  NEW_NODES=${NEW_NODES:-?}
  NEW_USERS=${NEW_USERS:-?}
  NEW_FILES=${NEW_FILES:-?}
  compare_count "节点" "$NEW_NODES" "$OLD_NODES"
  compare_count "用户" "$NEW_USERS" "$OLD_USERS"
  compare_count "文件" "$NEW_FILES" "$OLD_FILES"
  if assert_bootstrap; then
    BOOTSTRAP_VALUE="Successful"
  else
    BOOTSTRAP_VALUE="Failed"
    STEP_FAILED=1
  fi
  HTTP_CODE=$(http_code_for "$DOMAIN")
  log_line "首页 HTTP ${HTTP_CODE}，Host=${DOMAIN}"
  if [[ "$HTTP_CODE" =~ ^5[0-9][0-9]$ ]]; then
    print_http_errors
  fi
  if [[ "$NEW_NODES" == "$OLD_NODES" && "$NEW_USERS" == "$OLD_USERS" && "$NEW_FILES" == "$OLD_FILES" \
    && "$NEW_NODES" =~ ^[0-9]+$ && "$BOOTSTRAP_VALUE" == "Successful" && "$STEP_FAILED" -eq 0 ]] \
    && http_is_good "$HTTP_CODE"; then
    FINAL_OVERALL="成功"
  else
    FINAL_OVERALL="失败"
  fi
}

# --- import 步骤 7：写验收摘要 ---
import_write_report() {
  write_report
}

# --- import 步骤 8：导入后的账号、DNS 和旧站保留提示 ---
import_print_hints() {
  cat <<EOF | tee -a "$LOG"

导入后的管理员账号是旧站的，不是 install-restore.sh 生成的 admin。
切 DNS 前先用 hosts 文件或 curl 带 Host 头测试。
旧服务器至少保留几天。
EOF
}

import_main() {
  import_verify_pack
  import_ensure_codebase
  import_safety_gate
  import_backup_existing
  OVERWRITE_STARTED=1
  import_enable_maintenance
  import_database
  import_extract_files
  import_extract_private
  import_confirm_private_path
  import_chown_files
  import_update_database
  import_rebuild_cache
  import_disable_maintenance
  import_warn_domain
  import_acceptance
  import_write_report
  import_print_hints
  if [[ "$FINAL_OVERALL" != "成功" ]]; then
    die "搬家验收未通过。摘要已写入 ${REPORT}。"
  fi
  log_line "import 完成。"
}

# --- rollback 步骤 1：定位 sql.gz 和同时间戳的 files.tgz ---
rollback_resolve_backup() {
  local sibling
  require_cmd php tar gzip find awk sed curl stat flock
  validate_sql_gz "$BACKUP" || die "备份不是有效的数据库压缩包。没有修改站点。"
  sibling="${BACKUP%.sql.gz}-files.tgz"
  printf '%s\n' "$sibling" >"$WORK/rollback-files.txt"
  if [[ -f "$sibling" ]]; then
    log_line "找到同时间戳的文件备份：${sibling}"
    extract_checked_tar "$sibling" "$WORK/rollback-unpack" "回滚文件" || die "文件备份无法解压或路径不安全。没有修改站点。"
    if [[ ! -d "$WORK/rollback-unpack/files" ]]; then
      die "文件备份里没有 files 目录。没有修改站点。"
    fi
  else
    warn "同目录没有 ${sibling}。这次只恢复数据库，不替换上传文件。"
  fi
}

rollback_detect_host() {
  local report pattern host base
  host=""
  if [[ -f "$ROOT/web/sites/default/settings.php" ]]; then
    report=$(read_settings_report || true)
    pattern=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PATTERN" { print $2; exit }')
    if [[ -n "$pattern" ]]; then
      # shellcheck disable=SC2016
      host=$(php -r '
        $pattern = $argv[1];
        $pattern = preg_replace("/^\^/", "", $pattern);
        $pattern = preg_replace("/\$$/", "", $pattern);
        $pattern = str_replace("\\.", ".", $pattern);
        if (preg_match("/^[A-Za-z0-9.-]+$/", $pattern)) {
          echo $pattern;
        }
      ' "$pattern")
    fi
  fi
  if [[ -z "$host" ]]; then
    if base=$(drush_stdout config:get simple_sitemap.settings base_url --format=string); then
      base=$(printf '%s\n' "$base" | awk 'NF { print; exit }')
      host=$(host_of_url "$base")
    fi
  fi
  if [[ -z "$host" ]]; then
    host=$(hostname -f 2>/dev/null || hostname)
    warn "无法从 trusted_host_patterns 得到域名，首页检查改用 ${host}。"
  fi
  printf '%s' "$host"
}

rollback_restore_files() {
  local archive extracted path dest
  archive=$(tr -d '\r\n' <"$WORK/rollback-files.txt")
  if [[ ! -f "$archive" ]]; then
    return 0
  fi
  extracted="$WORK/rollback-unpack"
  if [[ ! -d "$extracted/files" ]]; then
    die "文件备份尚未解压。数据库已经替换，回滚前的数据库在 ${PREMIGRATE_SQL}。"
  fi
  replace_public_files_from_dir "$extracted/files"
  if [[ -f "$extracted/private-path.txt" ]]; then
    path=$(head -n 1 "$extracted/private-path.txt" | tr -d '\r')
    dest="$path"
    assert_safe_delete_path "$dest" "回滚私有文件"
    if [[ -L "$dest" ]]; then
      die "回滚的私有文件路径是符号链接，拒绝删除其内容：${dest}"
    fi
    if [[ -d "$extracted/private-files" ]]; then
      mkdir -p "$dest"
      find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      tar -C "$extracted/private-files" -cf - . | tar -C "$dest" -xf -
      printf '%s\n' "$dest" >"$WORK/private-dest.txt"
      log_line "已恢复私有文件到 ${dest}。"
    fi
  fi
}

# --- rollback 步骤 2：确认、备份现状、恢复、清缓存、验收 ---
rollback_apply() {
  local ts host private_abs
  if [[ ! -d "$ROOT" ]]; then
    die "Drupal 根目录不存在：${ROOT}"
  fi
  init_drush || die "drush 不可用，没有修改站点。"
  assert_bootstrap || die "drush bootstrap 未成功，没有修改站点。"
  load_db_prefix || die "无法读取数据库前缀，没有修改站点。"
  ts=$(date '+%Y%m%d%H%M%S')
  PREMIGRATE_SQL="/root/xedc-prerollback-${ts}.sql.gz"
  PREMIGRATE_FILES="/root/xedc-prerollback-${ts}-files.tgz"
  private_abs=$(current_private_dir || true)
  backup_database "$PREMIGRATE_SQL" || die "回滚前的数据库备份失败。没有删除现有数据。"
  if ! backup_files_tree "$PREMIGRATE_FILES" "$private_abs"; then
    die "回滚前的文件备份失败。数据库备份留在 ${PREMIGRATE_SQL}。没有删除现有数据。"
  fi
  log_line "回滚前又做了一份当前数据备份：${PREMIGRATE_SQL} 和 ${PREMIGRATE_FILES}"
  enable_maintenance rollback || die "无法打开维护模式。没有删除现有数据。"
  OVERWRITE_STARTED=1
  drop_tables || die "drush sql:drop 失败。当前库的备份在 ${PREMIGRATE_SQL}。"
  import_sql_gz "$BACKUP" || die "恢复备份失败。当前库的备份在 ${PREMIGRATE_SQL}。"
  rollback_restore_files || die "数据库已恢复为指定备份，但文件恢复失败。回滚前的文件在 ${PREMIGRATE_FILES}。"
  private_abs=""
  if [[ -f "$WORK/private-dest.txt" ]]; then
    private_abs=$(tr -d '\r' <"$WORK/private-dest.txt")
  fi
  chown_web_files "$private_abs"
  if ! drush_run cr; then
    STEP_FAILED=1
    warn "drush cr 失败。"
  fi
  if ! disable_maintenance rollback; then
    STEP_FAILED=1
    warn "无法关闭维护模式。"
  fi
  load_db_prefix || true
  NEW_NODES=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}node_field_data\`" || true)
  NEW_USERS=$(sql_scalar "SELECT COUNT(*) FROM \`${DB_PREFIX}users\`" || true)
  NEW_FILES=$(count_site_files "$ROOT" "$private_abs" || true)
  NEW_NODES=${NEW_NODES:-?}
  NEW_USERS=${NEW_USERS:-?}
  NEW_FILES=${NEW_FILES:-?}
  if assert_bootstrap; then
    BOOTSTRAP_VALUE="Successful"
  else
    BOOTSTRAP_VALUE="Failed"
    STEP_FAILED=1
  fi
  host=$(rollback_detect_host)
  HTTP_CODE=$(http_code_for "$host")
  printf '回滚验收：节点=%s  用户=%s  文件=%s  bootstrap=%s  首页HTTP=%s  Host=%s\n' \
    "$NEW_NODES" "$NEW_USERS" "$NEW_FILES" "$BOOTSTRAP_VALUE" "$HTTP_CODE" "$host" | tee -a "$LOG"
  if [[ "$HTTP_CODE" =~ ^5[0-9][0-9]$ ]]; then
    print_http_errors
  fi
  if [[ "$STEP_FAILED" -ne 0 || "$BOOTSTRAP_VALUE" != "Successful" ]] || ! http_is_good "$HTTP_CODE"; then
    die "回滚命令已执行，但验收未通过。"
  fi
  log_line "rollback 完成。"
}

rollback_main() {
  rollback_resolve_backup
  rollback_apply
}

main() {
  parse_args "$@"
  require_root
  umask 077
  export DRUSH_NON_INTERACTIVE=1
  init_logging
  acquire_lock
  make_work
  case "$COMMAND" in
    export) export_main ;;
    import) import_main ;;
    rollback) rollback_main ;;
    *)
      usage
      exit 2
      ;;
  esac
}

trap 'on_err $LINENO' ERR
trap 'on_exit' EXIT
main "$@"
