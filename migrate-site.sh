#!/usr/bin/env bash
#
# migrate-site.sh — 把运行中的 Drupal 站点搬到另一台服务器，或在本机从备份包恢复。
#
# 代码以 GitHub 上的仓库为准。本脚本打包或恢复数据库与上传文件。
# export 默认不改数据库、不改上传文件、不改 settings.php。
# import 在数据库导入完成后，会改 settings.php 里的 trusted_host_patterns、
# 可选的 hash_salt、以及必要时的 file_private_path，并用配置 API 更新已知的
# 域名配置（例如 simple_sitemap.settings 的 base_url）。不改节点正文和菜单链接。
# 任何覆盖数据库或上传文件的步骤都会先把现状备份到 /root。
# 本脚本不改写 Git 历史，也不把备份包上传到任何远程仓库。
#
# 日志：/var/log/xedc-migrate.log
# 导入验收：/root/xedc-migrate-report.txt
#
# 用法：
#   ./migrate-site.sh export   [--root /var/www/drupal] [--out /root/xedc-migrate] [--maintenance] [--yes]
#   ./migrate-site.sh import   --pack <包路径> --domain <域名> [--old-domain <旧域名>] [--root /var/www/drupal] [--yes] [--force]
#   ./migrate-site.sh rollback --backup <import 前自动生成的备份文件> [--root /var/www/drupal] [--yes]

set -euo pipefail
set -E

COMMAND=""
ROOT="/var/www/drupal"
OUT="/root/xedc-migrate"
PACK=""
DOMAIN=""
OLD_DOMAIN=""
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
OLD_HOST=""
DOMAIN_LC=""
PRIVATE_NOTE=""
SETTINGS_NOTE=""
DOMAIN_SCAN_PATH=""
SETTINGS_BACKUP=""

usage() {
  cat <<'EOF'
用法：
  ./migrate-site.sh export   [--root /var/www/drupal] [--out /root/xedc-migrate] [--maintenance] [--yes]
  ./migrate-site.sh import   --pack <包路径> --domain <域名> [--old-domain <旧域名>] [--root /var/www/drupal] [--yes] [--force]
  ./migrate-site.sh rollback --backup <import 前自动生成的备份文件> [--root /var/www/drupal] [--yes]

export    在旧服务器打包数据库和上传文件。默认不修改站点。
import    在新服务器导入，或在同一台服务器上从备份包恢复。覆盖前自动备份。
rollback  用 import 自动生成的 sql.gz 回到导入之前。必须同时给出 --yes，否则只打印本说明。

export 发现未提交改动或未出现在本机远端跟踪分支上的提交时，会列出明细并停止，除非带 --yes。
import 发现目标库已有节点，或存在 uid>1 的用户时，必须同时带 --force 和 --yes。
import 的 --old-domain 可省略。省略时从包内 manifest 的旧站域名读取。
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
    -e 's/ghp_[A-Za-z0-9]+/ghp_***/g' \
    -e 's/^(hash_salt=).*/\1***/' \
    -e 's/(HASH_SALT=)[^[:space:]]+/\1***/g' \
    -e 's/(HASH_SALT_VALUE=)[^[:space:]]+/\1***/g'
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
      --root|--out|--pack|--domain|--old-domain|--backup)
        if [[ "$#" -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
          usage
          exit 2
        fi
        case "$arg" in
          --root) ROOT="$2" ;;
          --out) OUT="$2" ;;
          --pack) PACK="$2" ;;
          --domain) DOMAIN="$2" ;;
          --old-domain) OLD_DOMAIN="$2" ;;
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
      if [[ -n "$PACK" || -n "$DOMAIN" || -n "$OLD_DOMAIN" || -n "$BACKUP" ]]; then
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
      if [[ -z "$BACKUP" || -n "$PACK" || -n "$DOMAIN" || -n "$OLD_DOMAIN" || "$ASSUME_YES" -ne 1 ]]; then
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
    if [[ -n "$OLD_DOMAIN" && ! "$OLD_DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
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

show_manifest() {
  redact_stream <"$1"
}

pattern_for_host() {
  local escaped
  # shellcheck disable=SC2016
  escaped=$(printf '%s' "$1" | sed -e 's/[.[\*^$()+?{|\\]/\\&/g')
  printf '^%s$' "$escaped"
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
$public_base = $settings['file_public_base_url'] ?? '';
echo "PUBLIC_BASE\t", (string) $public_base, "\n";
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
  tmp=$(mktemp /root/xedc-migrate-report.XXXXXX)
  {
    printf '%s\n' "$line"
    if [[ -n "$PRIVATE_NOTE" ]]; then
      printf '%s\n' "$PRIVATE_NOTE"
    fi
    if [[ -n "$SETTINGS_NOTE" ]]; then
      printf '%s\n' "$SETTINGS_NOTE"
    fi
    if [[ -n "$DOMAIN_SCAN_PATH" && -f "$DOMAIN_SCAN_PATH" ]]; then
      printf '\n'
      cat "$DOMAIN_SCAN_PATH"
    fi
  } >"$tmp"
  redact_stream <"$tmp" | tee -a "$LOG"
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

backup_settings_file() {
  local dest="$1"
  local src="$ROOT/web/sites/default/settings.php"
  if [[ ! -f "$src" ]]; then
    log_err "没有可备份的 settings.php：${src}"
    return 1
  fi
  cp -p "$src" "$dest" || return 1
  chmod 600 "$dest"
  log_line "已备份 settings.php 到 ${dest}"
}

restore_settings_file() {
  local src="$1"
  local dest="$ROOT/web/sites/default/settings.php"
  local dir tmp err
  if [[ ! -f "$src" ]]; then
    log_err "找不到 settings.php 备份：${src}"
    return 1
  fi
  err=$(mktemp)
  if ! php -l "$src" >"$err" 2>&1; then
    log_err "settings.php 备份语法无效，没有覆盖现有文件。"
    print_captured_error "$err"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  dir=$(dirname "$dest")
  tmp=$(mktemp "$dir/settings.php.restore.XXXXXX")
  cp "$src" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if id www-data >/dev/null 2>&1; then
    chown root:www-data "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi
  chmod 640 "$tmp"
  mv -f "$tmp" "$dest" || return 1
  log_line "已恢复 settings.php。"
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

export_read_hash_salt() {
  local raw salt
  raw=$(drush_stdout php:eval 'echo "HASH_SALT=", (string) (\Drupal\Core\Site\Settings::get("hash_salt") ?? ""), "\n";') || return 1
  salt=$(printf '%s\n' "$raw" | sed -n 's/^HASH_SALT=//p' | tail -n 1 | tr -d '\r')
  if [[ "$salt" == *$'\n'* || "$salt" == *xedc-migrate:* ]]; then
    warn "hash_salt 含有换行或迁移标记，本次不写入 manifest。导入时将保留新 settings.php 里的值。"
    return 0
  fi
  printf '%s' "$salt"
}

# --- export 步骤 6：写 manifest.txt ---
export_write_manifest() {
  local now drupal_version php_version mariadb_version git_commit base old_domain hash_salt
  local node_rows user_rows file_rows private_raw private_abs db_hash pub_hash priv_hash
  now=$(date '+%F %T %z')
  drupal_version=$(drush_stdout status --field=drupal-version) || die "无法读取 Drupal 版本。"
  drupal_version=$(printf '%s\n' "$drupal_version" | awk 'NF { print; exit }')
  php_version=$(php -r 'echo PHP_VERSION;')
  mariadb_version=$(drush_stdout sql:query "SELECT VERSION()") || die "无法读取 MariaDB 版本。"
  mariadb_version=$(printf '%s\n' "$mariadb_version" | awk 'NF { line = $0 } END { print line }' | tr -d '\r')
  if [[ -z "$mariadb_version" || "$mariadb_version" == *$'\n'* || "$mariadb_version" == *"="* ]]; then
    die "MariaDB 版本无法写入 manifest。没有修改站点。"
  fi
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
  hash_salt=$(export_read_hash_salt) || die "无法读取 hash_salt。没有修改站点。"
  if [[ -n "$hash_salt" ]]; then
    log_line "manifest 将记录 hash_salt。日志和终端不打印该值。"
  else
    log_line "settings 中 hash_salt 为空，manifest 不记录。导入时保留新生成的值。"
  fi
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
    if [[ -n "$hash_salt" ]]; then
      printf 'hash_salt=%s\n' "$hash_salt"
    fi
    printf 'sha256 database.sql.gz %s\n' "$db_hash"
    printf 'sha256 public-files.tgz %s\n' "$pub_hash"
    if [[ -n "$priv_hash" ]]; then
      printf 'sha256 private-files.tgz %s\n' "$priv_hash"
    fi
  } >"$WORK/payload/manifest.txt"
  chmod 600 "$WORK/payload/manifest.txt"
  log_line "已生成 manifest。"
  show_manifest "$WORK/payload/manifest.txt" | tee -a "$LOG"
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

包含用户邮箱、密码哈希，以及可能包含 hash_salt。不要放进 GitHub，用完在两边删除。
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
  show_manifest "$manifest" | tee -a "$LOG"
  validate_sql_gz "$WORK/payload/database.sql.gz" || die "数据库包无效。站点没有改动。"
  import_stage_archives
}

import_stage_archives() {
  local manifest raw abs
  extract_checked_tar "$WORK/payload/public-files.tgz" "$WORK/public-unpack" "公共文件" || die "公共文件没有通过检查。站点没有改动。"
  if [[ ! -d "$WORK/public-unpack/files" ]]; then
    die "公共文件包里没有 files 目录。站点没有改动。"
  fi
  manifest="$WORK/payload/manifest.txt"
  raw=$(manifest_value "私有文件路径" "$manifest")
  abs=$(manifest_value "私有文件绝对路径" "$manifest")
  if [[ ! -f "$WORK/payload/private-files.tgz" ]]; then
    if [[ -n "$raw" || -n "$abs" ]]; then
      warn "manifest 记录了私有文件路径，但包内没有 private-files.tgz。"
    fi
    printf '\n' >"$WORK/private-dest.txt"
    return 0
  fi
  if [[ -z "$raw" && -z "$abs" ]]; then
    die "有 private-files.tgz，但 manifest 没有私有文件路径。站点没有改动。"
  fi
  extract_checked_tar "$WORK/payload/private-files.tgz" "$WORK/private-unpack" "私有文件" || die "私有文件没有通过检查。站点没有改动。"
  log_line "私有文件已在临时目录校验通过。最终目录在读取 settings.php 之后决定。"
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
  SETTINGS_BACKUP="/root/xedc-premigrate-${ts}-settings.php"
  private_abs=$(current_private_dir || true)
  backup_database "$PREMIGRATE_SQL" || die "覆盖前数据库备份失败。没有删除现有数据。"
  if ! backup_files_tree "$PREMIGRATE_FILES" "$private_abs"; then
    die "覆盖前文件备份失败。数据库备份留在 ${PREMIGRATE_SQL}。没有删除现有数据。"
  fi
  if ! backup_settings_file "$SETTINGS_BACKUP"; then
    die "覆盖前 settings.php 备份失败。数据库备份留在 ${PREMIGRATE_SQL}。没有删除现有数据。"
  fi
  log_line "覆盖前备份：数据库 ${PREMIGRATE_SQL}"
  log_line "覆盖前备份：文件 ${PREMIGRATE_FILES}"
  log_line "覆盖前备份：settings.php ${SETTINGS_BACKUP}"
  log_line "回滚命令：${0} rollback --backup ${PREMIGRATE_SQL} --root ${ROOT} --yes"
  printf '\n覆盖前备份：\n数据库：%s\n文件：%s\nsettings.php：%s\n回滚命令：\n  %s rollback --backup %s --root %s --yes\n同时间戳的 -settings.php 会在 rollback 时一并恢复。\n\n' \
    "$PREMIGRATE_SQL" "$PREMIGRATE_FILES" "$SETTINGS_BACKUP" "$0" "$PREMIGRATE_SQL" "$ROOT" | tee -a "$LOG"
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
  dest=$(tr -d '\r\n' <"$WORK/private-dest.txt" || true)
  if [[ -z "$dest" ]]; then
    if [[ -f "$WORK/payload/private-files.tgz" ]]; then
      die "私有文件还没有确定解压目录。数据库已经导入，可使用回滚命令。"
    fi
    log_line "没有需要放入站点的私有文件。"
    return 0
  fi
  if [[ ! -d "$WORK/private-unpack" ]]; then
    die "私有文件还没有解压到临时目录。数据库已经导入，可使用回滚命令。"
  fi
  files_dir="$ROOT/web/sites/default/files"
  assert_safe_delete_path "$dest" "私有文件目录"
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

private_dest_allowed() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    return 1
  fi
  case "$path" in
    /|/root|/root/*|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/lib64|/lib64/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*|/tmp|/tmp/*|/var|/var/log|/var/log/*|/home|/opt|/srv)
      return 1
      ;;
  esac
  if [[ "${path#/}" != */* ]]; then
    return 1
  fi
  case "$path" in
    "$ROOT"|"$ROOT/web"|"$ROOT/web/sites"|"$ROOT/web/sites/default"|"$ROOT/web/sites/default/files")
      return 1
      ;;
  esac
  if [[ -L "$path" ]]; then
    return 1
  fi
  return 0
}

resolve_private_setting() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    return 0
  fi
  if [[ "$raw" == /* ]]; then
    readlink -m "$raw"
  else
    readlink -m "$ROOT/web/$raw"
  fi
}

append_pattern_file() {
  local file="$1"
  local item="$2"
  if [[ -z "$item" ]]; then
    return 0
  fi
  if [[ "$item" == *$'\n'* || "$item" == *xedc-migrate:* || ${#item} -gt 200 ]]; then
    warn "跳过无法安全保留的 trusted_host_patterns 项。"
    return 0
  fi
  if grep -Fxq -e "$item" "$file"; then
    return 0
  fi
  printf '%s\n' "$item" >>"$file"
}

resolve_old_host() {
  local manifest_host
  manifest_host=$(manifest_value "旧站域名" "$WORK/payload/manifest.txt")
  manifest_host=$(printf '%s' "$manifest_host" | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  if [[ -n "$OLD_DOMAIN" ]]; then
    OLD_HOST=$(printf '%s' "$OLD_DOMAIN" | tr '[:upper:]' '[:lower:]')
    if [[ -n "$manifest_host" && "$OLD_HOST" != "$manifest_host" ]]; then
      warn "--old-domain ${OLD_HOST} 与 manifest 的旧站域名 ${manifest_host} 不同，按命令行参数处理。"
    fi
  else
    OLD_HOST="$manifest_host"
  fi
  if [[ -n "$OLD_HOST" && ! "$OLD_HOST" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]; then
    warn "旧域名格式无效，跳过按旧域名的配置更新和残留扫描。"
    OLD_HOST=""
  fi
  DOMAIN_LC=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  log_line "旧域名：${OLD_HOST:-（无）}。新域名：${DOMAIN_LC}。"
}

# 私有文件优先解压到 settings.php 已有的 file_private_path。
# 该值为空或不能安全使用时，改用 $ROOT/private（或仍在站点根目录下的原路径），并写回 settings.php。
import_finalize_private_dest() {
  local manifest raw abs report settings_raw settings_resolved manifest_resolved dest
  : >"$WORK/private-settings-update.txt"
  manifest="$WORK/payload/manifest.txt"
  raw=$(manifest_value "私有文件路径" "$manifest")
  abs=$(manifest_value "私有文件绝对路径" "$manifest")
  if [[ ! -f "$WORK/payload/private-files.tgz" ]]; then
    printf '\n' >"$WORK/private-dest.txt"
    PRIVATE_NOTE="私有文件：包内没有私有文件。"
    log_line "$PRIVATE_NOTE"
    return 0
  fi
  if [[ ! -d "$WORK/private-unpack" ]]; then
    die "私有文件还没有在临时目录解压。数据库已经导入，可使用回滚命令。"
  fi
  report=$(read_settings_report) || die "无法读取 settings.php，不能对齐私有文件路径。数据库已经导入，可使用回滚命令。"
  settings_raw=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PRIVATE" { print $2; exit }')
  settings_resolved=""
  if [[ -n "$settings_raw" ]]; then
    settings_resolved=$(resolve_private_setting "$settings_raw")
  fi
  manifest_resolved=""
  if [[ -n "$abs" ]]; then
    manifest_resolved=$(readlink -m "$abs")
  elif [[ "$raw" == /* ]]; then
    manifest_resolved=$(readlink -m "$raw")
  elif [[ -n "$raw" ]]; then
    manifest_resolved=$(readlink -m "$ROOT/web/$raw")
  fi
  if [[ -n "$settings_resolved" ]] && private_dest_allowed "$settings_resolved"; then
    dest="$settings_resolved"
    if [[ -n "$manifest_resolved" && "$manifest_resolved" != "$dest" ]]; then
      PRIVATE_NOTE="警告：私有文件改解压到 settings.php 的 file_private_path（${dest}）。导出时的绝对路径是 ${manifest_resolved}。已调整解压目标，使 Drupal 能找到这些文件。未改 file_private_path。"
      warn "$PRIVATE_NOTE"
    else
      PRIVATE_NOTE="私有文件：解压路径与 file_private_path 一致（${dest}）。"
      log_line "$PRIVATE_NOTE"
    fi
  else
    if [[ -n "$settings_raw" ]]; then
      warn "settings.php 的 file_private_path（${settings_raw}）不能作为解压目录。"
    fi
    dest=""
    if [[ -n "$manifest_resolved" && "$manifest_resolved" == "$ROOT"/* ]] && private_dest_allowed "$manifest_resolved"; then
      dest="$manifest_resolved"
    else
      dest="$ROOT/private"
    fi
    if ! private_dest_allowed "$dest"; then
      die "没有安全的私有文件目录可用。数据库已经导入，可使用回滚命令。"
    fi
    printf '%s\n' "$dest" >"$WORK/private-settings-update.txt"
    PRIVATE_NOTE="警告：file_private_path 为空或不能使用。私有文件将解压到 ${dest}，并写入 settings.php 的 file_private_path。"
    if [[ -n "$manifest_resolved" && "$manifest_resolved" != "$dest" ]]; then
      PRIVATE_NOTE="${PRIVATE_NOTE} 导出时的绝对路径是 ${manifest_resolved}。"
    fi
    warn "$PRIVATE_NOTE"
  fi
  printf '%s\n' "$dest" >"$WORK/private-dest.txt"
  log_line "私有文件最终目录：${dest}"
}

settings_adapt_fail() {
  local msg="$1"
  local src="$WORK/settings.php.before-adapt"
  local dest="$ROOT/web/sites/default/settings.php"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest" || true
    if [[ -n "${SETTINGS_MODE:-}" ]]; then
      chmod "$SETTINGS_MODE" "$dest" || true
    fi
    if [[ -n "${SETTINGS_OWNER:-}" ]]; then
      chown "$SETTINGS_OWNER" "$dest" || true
    fi
    log_err "已把 settings.php 恢复为域名适配之前的内容。"
  fi
  die "$msg"
}

import_apply_settings() {
  local settings report key pattern host required_www patterns_file salt
  local write_salt private_path write_private public_raw new_public write_public
  local note_salt note_public php_err rc verify_out dir tmp
  settings="$ROOT/web/sites/default/settings.php"
  [[ -f "$settings" ]] || die "找不到 settings.php，无法做域名适配。数据库已经导入，可使用回滚命令。"
  resolve_old_host
  report=$(read_settings_report) || die "无法读取 settings.php。数据库已经导入，可使用回滚命令。"
  patterns_file="$WORK/trusted-patterns.txt"
  : >"$patterns_file"
  chmod 600 "$patterns_file"
  while IFS=$'\t' read -r key pattern; do
    [[ "$key" == "PATTERN" ]] || continue
    append_pattern_file "$patterns_file" "$pattern"
  done <<<"$report"
  append_pattern_file "$patterns_file" "$(pattern_for_host "$DOMAIN_LC")"
  required_www=""
  if [[ "$DOMAIN_LC" == www.* ]]; then
    host="${DOMAIN_LC#www.}"
  else
    host="www.${DOMAIN_LC}"
  fi
  if [[ "$host" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]; then
    required_www=$(pattern_for_host "$host")
    append_pattern_file "$patterns_file" "$required_www"
  fi
  if ! grep -Fxq -e "$(pattern_for_host "$DOMAIN_LC")" "$patterns_file"; then
    die "无法生成新域名的 trusted_host_patterns。数据库已经导入，可使用回滚命令。"
  fi

  salt=$(manifest_value "hash_salt" "$WORK/payload/manifest.txt")
  salt=${salt//$'\r'/}
  write_salt=0
  note_salt=""
  if [[ -z "$salt" ]]; then
    note_salt="manifest 没有 hash_salt，保留 settings.php 里现有的值。Drupal 8 及以上的用户密码哈希不依赖 hash_salt。"
  elif [[ "$salt" == *$'\n'* || "$salt" == *xedc-migrate:* || ${#salt} -lt 8 || ${#salt} -gt 512 ]]; then
    note_salt="manifest 里的 hash_salt 无法安全写回，保留 settings.php 里现有的值。"
    warn "$note_salt"
    salt=""
  else
    write_salt=1
    note_salt="已把导出的 hash_salt 写入 settings.php。日志不打印该值。Drupal 8 及以上的用户密码哈希不依赖它，写回是为了一次性登录链接和部分 token。"
  fi

  private_path=""
  write_private=0
  if [[ -s "$WORK/private-settings-update.txt" ]]; then
    private_path=$(tr -d '\r\n' <"$WORK/private-settings-update.txt")
    if [[ -n "$private_path" ]]; then
      write_private=1
    fi
  fi

  public_raw=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PUBLIC_BASE" { print $2; exit }')
  new_public=""
  write_public=0
  note_public=""
  if [[ -n "$public_raw" && -n "$OLD_HOST" ]]; then
    # shellcheck disable=SC2016
    new_public=$(php -r '
      $raw = (string) ($argv[1] ?? "");
      $old = strtolower((string) ($argv[2] ?? ""));
      $new = strtolower((string) ($argv[3] ?? ""));
      $parts = parse_url($raw);
      if (!is_array($parts) || empty($parts["host"]) || strtolower((string) $parts["host"]) !== $old) {
        exit(0);
      }
      $scheme = $parts["scheme"] ?? "https";
      if ($scheme !== "http" && $scheme !== "https") {
        $scheme = "https";
      }
      $path = $parts["path"] ?? "";
      if ($path === "/") {
        $path = "";
      }
      $port = isset($parts["port"]) ? ":" . $parts["port"] : "";
      $query = isset($parts["query"]) ? "?" . $parts["query"] : "";
      echo $scheme, "://", $new, $port, $path, $query;
    ' "$public_raw" "$OLD_HOST" "$DOMAIN_LC" || true)
    if [[ -n "$new_public" && "$new_public" != "$public_raw" ]]; then
      write_public=1
      note_public="已把 file_public_base_url 的主机改为 ${DOMAIN_LC}。"
    fi
  fi

  cp -p "$settings" "$WORK/settings.php.before-adapt"
  chmod 600 "$WORK/settings.php.before-adapt"
  SETTINGS_MODE=$(stat -c '%a' "$settings")
  SETTINGS_OWNER=$(stat -c '%u:%g' "$settings")
  php_err=$(mktemp)
  set +e
  SETTINGS_PATH="$settings" \
    SETTINGS_OUT="$WORK/settings.php.new" \
    PATTERNS_FILE="$patterns_file" \
    WRITE_SALT="$write_salt" \
    HASH_SALT_VALUE="$salt" \
    WRITE_PRIVATE="$write_private" \
    PRIVATE_PATH_VALUE="$private_path" \
    WRITE_PUBLIC="$write_public" \
    PUBLIC_BASE_VALUE="$new_public" \
    php <<'PHP' >"$php_err" 2>&1
<?php
$settings_path = getenv('SETTINGS_PATH');
$out_path = getenv('SETTINGS_OUT');
$patterns_file = getenv('PATTERNS_FILE');
$raw = file_get_contents($settings_path);
if ($raw === false) {
  fwrite(STDERR, "无法读取 settings.php\n");
  exit(1);
}
$raw = preg_replace("#\n?// xedc-migrate:begin\n.*?\n// xedc-migrate:end\n#s", "\n", $raw);
if (!is_string($raw)) {
  fwrite(STDERR, "无法清理旧的迁移标记\n");
  exit(1);
}
$lines = file($patterns_file, FILE_IGNORE_NEW_LINES);
if ($lines === false) {
  fwrite(STDERR, "无法读取域名模式\n");
  exit(1);
}
$patterns = [];
foreach ($lines as $line) {
  if ($line === '') {
    continue;
  }
  if (str_contains($line, "\n") || str_contains($line, 'xedc-migrate:') || strlen($line) > 200) {
    fwrite(STDERR, "域名模式无效\n");
    exit(1);
  }
  $patterns[] = $line;
}
$patterns = array_values(array_unique($patterns));
if ($patterns === []) {
  fwrite(STDERR, "没有可写入的 trusted_host_patterns\n");
  exit(1);
}
$block = "\n// xedc-migrate:begin\n";
$block .= "// Written by migrate-site.sh. Later assignments override earlier ones.\n";
$block .= '$settings[\'trusted_host_patterns\'] = ' . var_export($patterns, true) . ";\n";
if (getenv('WRITE_SALT') === '1') {
  $salt = getenv('HASH_SALT_VALUE');
  if (!is_string($salt) || $salt === '' || str_contains($salt, "\n") || str_contains($salt, "\0") || str_contains($salt, 'xedc-migrate:')) {
    fwrite(STDERR, "hash_salt 无法安全写入\n");
    exit(1);
  }
  $block .= '$settings[\'hash_salt\'] = ' . var_export($salt, true) . ";\n";
}
if (getenv('WRITE_PRIVATE') === '1') {
  $private = getenv('PRIVATE_PATH_VALUE');
  if (!is_string($private) || $private === '' || $private[0] !== '/' || str_contains($private, "\n") || str_contains($private, "\0")) {
    fwrite(STDERR, "file_private_path 无法安全写入\n");
    exit(1);
  }
  $block .= '$settings[\'file_private_path\'] = ' . var_export($private, true) . ";\n";
}
if (getenv('WRITE_PUBLIC') === '1') {
  $public = getenv('PUBLIC_BASE_VALUE');
  if (!is_string($public) || !preg_match('#^https?://#', $public) || str_contains($public, "\n")) {
    fwrite(STDERR, "file_public_base_url 无法安全写入\n");
    exit(1);
  }
  $block .= '$settings[\'file_public_base_url\'] = ' . var_export($public, true) . ";\n";
}
$block .= "// xedc-migrate:end\n";
if (!str_ends_with($raw, "\n")) {
  $raw .= "\n";
}
if (file_put_contents($out_path, $raw . $block) === false) {
  fwrite(STDERR, "无法写入新的 settings.php\n");
  exit(1);
}
PHP
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    log_err "生成新的 settings.php 失败。"
    print_captured_error "$php_err"
    rm -f "$php_err" "$WORK/settings.php.new"
    die "settings.php 没有被替换。数据库已经导入，可使用回滚命令。"
  fi
  rm -f "$php_err"
  if ! php -l "$WORK/settings.php.new" >/dev/null 2>&1; then
    rm -f "$WORK/settings.php.new"
    die "新的 settings.php 语法无效，原文件没有替换。数据库已经导入，可使用回滚命令。"
  fi
  verify_out=$(mktemp)
  set +e
  CHECK_DOMAIN="$DOMAIN_LC" \
    REQUIRED_PATTERN="$(pattern_for_host "$DOMAIN_LC")" \
    REQUIRED_WWW="$required_www" \
    WRITE_SALT="$write_salt" \
    HASH_SALT_VALUE="$salt" \
    WRITE_PRIVATE="$write_private" \
    PRIVATE_PATH_VALUE="$private_path" \
    WRITE_PUBLIC="$write_public" \
    PUBLIC_BASE_VALUE="$new_public" \
    SETTINGS_PATH="$WORK/settings.php.new" \
    APP_ROOT="$ROOT/web" \
    php <<'PHP' >"$verify_out" 2>&1
<?php
$settings = [];
$databases = [];
$config = [];
$app_root = getenv('APP_ROOT');
$site_path = 'sites/default';
include getenv('SETTINGS_PATH');
$patterns = $settings['trusted_host_patterns'] ?? [];
if (!is_array($patterns)) {
  fwrite(STDERR, "trusted_host_patterns 不是数组\n");
  exit(1);
}
$required = getenv('REQUIRED_PATTERN');
$required_www = getenv('REQUIRED_WWW');
if (!in_array($required, $patterns, true)) {
  fwrite(STDERR, "缺少新域名模式\n");
  exit(1);
}
if (is_string($required_www) && $required_www !== '' && !in_array($required_www, $patterns, true)) {
  fwrite(STDERR, "缺少 www 或裸域名模式\n");
  exit(1);
}
$domain = (string) getenv('CHECK_DOMAIN');
$matched = false;
foreach ($patterns as $pattern) {
  if (!is_string($pattern)) {
    continue;
  }
  if (@preg_match('{' . $pattern . '}i', $domain) === 1) {
    $matched = true;
  }
}
if (!$matched) {
  fwrite(STDERR, "trusted_host_patterns 没有匹配新域名\n");
  exit(1);
}
if (getenv('WRITE_SALT') === '1' && (($settings['hash_salt'] ?? null) !== getenv('HASH_SALT_VALUE'))) {
  fwrite(STDERR, "hash_salt 没有写回成功\n");
  exit(2);
}
if (getenv('WRITE_PRIVATE') === '1' && (($settings['file_private_path'] ?? '') !== getenv('PRIVATE_PATH_VALUE'))) {
  fwrite(STDERR, "file_private_path 没有写回成功\n");
  exit(3);
}
if (getenv('WRITE_PUBLIC') === '1' && (($settings['file_public_base_url'] ?? '') !== getenv('PUBLIC_BASE_VALUE'))) {
  fwrite(STDERR, "file_public_base_url 没有写回成功\n");
  exit(4);
}
echo "SETTINGS_OK\n";
PHP
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]] || ! grep -q '^SETTINGS_OK$' "$verify_out"; then
    log_err "新的 settings.php 校验失败。"
    print_captured_error "$verify_out"
    rm -f "$verify_out" "$WORK/settings.php.new"
    die "settings.php 没有被替换。数据库已经导入，可使用回滚命令。"
  fi
  rm -f "$verify_out"
  dir=$(dirname "$settings")
  tmp=$(mktemp "$dir/settings.php.migrate.XXXXXX")
  cp "$WORK/settings.php.new" "$tmp" || { rm -f "$tmp"; settings_adapt_fail "无法复制新的 settings.php。数据库已经导入，可使用回滚命令。"; }
  chmod "$SETTINGS_MODE" "$tmp" || { rm -f "$tmp"; settings_adapt_fail "无法设置 settings.php 权限。数据库已经导入，可使用回滚命令。"; }
  chown "$SETTINGS_OWNER" "$tmp" || { rm -f "$tmp"; settings_adapt_fail "无法设置 settings.php 所有者。数据库已经导入，可使用回滚命令。"; }
  mv -f "$tmp" "$settings" || { rm -f "$tmp"; settings_adapt_fail "无法替换 settings.php。数据库已经导入，可使用回滚命令。"; }
  rm -f "$WORK/settings.php.new"
  SETTINGS_NOTE="域名适配：trusted_host_patterns 已包含 $(pattern_for_host "$DOMAIN_LC")"
  if [[ -n "$required_www" ]]; then
    SETTINGS_NOTE="${SETTINGS_NOTE} 和 ${required_www}"
  fi
  SETTINGS_NOTE="${SETTINGS_NOTE}。${note_salt}"
  if [[ -n "$note_public" ]]; then
    SETTINGS_NOTE="${SETTINGS_NOTE}${note_public}"
  fi
  log_line "$SETTINGS_NOTE"
  reload_php_fpm
}

reload_php_fpm() {
  local unit name
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  while read -r unit _; do
    [[ -n "$unit" ]] || continue
    name="${unit%.service}"
    if systemctl reload "$name"; then
      log_line "已 reload ${name}。"
    else
      warn "reload ${name} 失败。若首页返回 400，请手动 reload PHP-FPM。"
    fi
  done < <(systemctl list-units --type=service --no-legend 'php*-fpm.service' 2>/dev/null || true)
}

import_verify_private_alignment() {
  local dest report settings_private resolved
  dest=$(tr -d '\r\n' <"$WORK/private-dest.txt" || true)
  if [[ -z "$dest" ]]; then
    return 0
  fi
  report=$(read_settings_report) || die "无法再读 settings.php 核对私有路径。数据库已经导入，可使用回滚命令。"
  settings_private=$(printf '%s\n' "$report" | awk -F '\t' '$1 == "PRIVATE" { print $2; exit }')
  if [[ -z "$settings_private" ]]; then
    die "settings.php 仍然没有 file_private_path，但私有文件已解压到 ${dest}。可使用回滚命令。"
  fi
  resolved=$(resolve_private_setting "$settings_private")
  if [[ "$resolved" != "$(readlink -m "$dest")" ]]; then
    die "私有文件目录 ${dest} 与 file_private_path（${settings_private}，解析为 ${resolved}）仍然不一致。可使用回滚命令。"
  fi
  log_line "已核对：私有文件目录与 file_private_path 一致。"
}

# 只改已知的标量 URL。不扫描 SQL，不改序列化字段，不改节点正文和菜单链接。
# 允许：simple_sitemap.settings:base_url。
# 不改：邮件、SMTP、Matomo 子域、Metatag（含序列化）、用户内容。
import_apply_domain_config() {
  local php out err rc summary
  php=$(mktemp "$WORK/domain-config.XXXXXX.php")
  cat >"$php" <<'PHP'
<?php

$newHost = strtolower((string) getenv('NEW_HOST'));
if ($newHost === '') {
  fwrite(STDERR, "缺少新域名\n");
  exit(1);
}
$allow = [
  'simple_sitemap.settings' => ['base_url'],
];
$factory = \Drupal::configFactory();
foreach ($allow as $name => $keys) {
  $editable = $factory->getEditable($name);
  if ($editable->isNew()) {
    echo "SKIP\t{$name}\t配置不存在\n";
    continue;
  }
  foreach ($keys as $key) {
    $current = $editable->get($key);
    if (!is_string($current) || $current === '') {
      echo "SKIP\t{$name}\t{$key}\t不是非空字符串\n";
      continue;
    }
    if (preg_match('/^[aObis]:\d+:/', $current) === 1) {
      echo "SKIP\t{$name}\t{$key}\t疑似序列化，不改写\n";
      continue;
    }
    $parts = parse_url($current);
    if (!is_array($parts) || empty($parts['host'])) {
      echo "SKIP\t{$name}\t{$key}\t不是绝对 URL\n";
      continue;
    }
    $scheme = $parts['scheme'] ?? 'https';
    if ($scheme !== 'http' && $scheme !== 'https') {
      $scheme = 'https';
    }
    $path = $parts['path'] ?? '';
    if ($path === '/') {
      $path = '';
    }
    $port = isset($parts['port']) ? ':' . $parts['port'] : '';
    $query = isset($parts['query']) ? '?' . $parts['query'] : '';
    $fragment = isset($parts['fragment']) ? '#' . $parts['fragment'] : '';
    $updated = $scheme . '://' . $newHost . $port . $path . $query . $fragment;
    if ($updated === $current) {
      echo "UNCHANGED\t{$name}\t{$key}\n";
      continue;
    }
    try {
      $editable->set($key, $updated)->save();
    } catch (Throwable $exception) {
      fwrite(STDERR, "更新 {$name} {$key} 失败：" . $exception::class . "\n");
      exit(1);
    }
    echo "UPDATED\t{$name}\t{$key}\t{$updated}\n";
  }
}
PHP
  out=$(mktemp)
  err=$(mktemp)
  set +e
  OLD_HOST="${OLD_HOST}" NEW_HOST="${DOMAIN_LC}" "${DRUSH[@]}" php:script "$php" >"$out" 2>"$err"
  rc=$?
  set -e
  if [[ -s "$out" ]]; then
    redact_stream <"$out" | tee -a "$LOG"
  fi
  if [[ "$rc" -ne 0 ]]; then
    STEP_FAILED=1
    log_err "更新已知域名配置失败。"
    print_captured_error "$err" "$out"
  elif [[ -s "$err" ]]; then
    redact_file "$err" >>"$LOG"
  fi
  rm -f "$err"
  summary=$(awk -F '\t' '$1 == "UPDATED" { printf "%s:%s=%s; ", $2, $3, $4 }' "$out")
  rm -f "$out"
  if [[ -n "$summary" ]]; then
    SETTINGS_NOTE="${SETTINGS_NOTE} 已用配置 API 更新：${summary}"
    log_line "已用配置 API 更新：${summary}"
  elif [[ "$rc" -eq 0 ]]; then
    SETTINGS_NOTE="${SETTINGS_NOTE} 已知域名配置无需改写，或对应配置不存在。"
    log_line "已知域名配置无需改写，或对应配置不存在。"
  else
    SETTINGS_NOTE="${SETTINGS_NOTE} 已知域名配置更新失败，详见日志。"
  fi
}

import_scan_leftover_domain() {
  local php out err rc files_dir hit shown
  DOMAIN_SCAN_PATH="$WORK/domain-scan.txt"
  : >"$DOMAIN_SCAN_PATH"
  chmod 600 "$DOMAIN_SCAN_PATH"
  if [[ -z "$OLD_HOST" || "$OLD_HOST" == "$DOMAIN_LC" ]]; then
    printf '残留旧域名：新旧域名相同或没有旧域名，跳过扫描。\n' >>"$DOMAIN_SCAN_PATH"
    log_line "残留旧域名：新旧域名相同或没有旧域名，跳过扫描。"
    return 0
  fi
  php=$(mktemp "$WORK/domain-scan.XXXXXX.php")
  cat >"$php" <<'PHP'
<?php

$old = strtolower((string) getenv('OLD_HOST'));
$new = strtolower((string) getenv('NEW_HOST'));
if ($old === '' || strcasecmp($old, $new) === 0) {
  echo "残留旧域名：没有可扫描的旧域名。\n";
  return;
}
echo "残留旧域名扫描（只报告，不改写节点正文、菜单链接和其他用户内容）：\n";

function host_mentioned(string $value, string $old): bool {
  $quoted = preg_quote($old, '/');
  $pattern = '/(?<![A-Za-z0-9-])(?:[A-Za-z0-9-]+\.)*' . $quoted . '(?![A-Za-z0-9.-])/i';
  return preg_match($pattern, $value) === 1;
}

$shown = 0;
$truncated = false;
foreach (\Drupal::configFactory()->listAll() as $name) {
  $data = \Drupal::config($name)->getRawData();
  $keys = [];
  $walk = function ($value, $key) use (&$walk, &$keys, $old) {
    if (is_array($value)) {
      foreach ($value as $child_key => $child) {
        $next = $key === '' ? (string) $child_key : $key . '.' . $child_key;
        $walk($child, $next);
      }
      return;
    }
    if (!is_string($value) || !host_mentioned($value, $old)) {
      return;
    }
    if (preg_match('/pass|secret|token|salt|credential|api_key/i', (string) $key) === 1) {
      return;
    }
    $keys[] = $key === '' ? '(root)' : $key;
  };
  $walk($data, '');
  foreach ($keys as $key) {
    if ($shown >= 50) {
      $truncated = true;
      break 2;
    }
    echo "配置 ", $name, " ", $key, "\n";
    $shown++;
  }
}
if ($truncated) {
  echo "（还有更多包含旧域名的配置，已停止列举）\n";
}
if ($shown === 0) {
  echo "配置中没有再发现旧域名。\n";
}

$quoted = str_replace('.', '\\.', $old);
$body_re = '(^|[^A-Za-z0-9-])([A-Za-z0-9-]+\\.)*' . $quoted . '([^A-Za-z0-9.-]|$)';
$mail_re = '@([A-Za-z0-9-]+\\.)*' . $quoted . '$';
$checks = [
  ['node__body', 'body_value', $body_re, 'node__body.body_value'],
  ['menu_link_content_data', 'link__uri', $body_re, 'menu_link_content_data.link__uri'],
  ['users_field_data', 'mail', $mail_re, 'users_field_data.mail'],
];
$database = \Drupal::database();
$schema = $database->schema();
foreach ($checks as [$table, $column, $pattern, $label]) {
  if (!$schema->tableExists($table) || !$schema->fieldExists($table, $column)) {
    echo $label, " 不存在，跳过。\n";
    continue;
  }
  $sql = 'SELECT COUNT(*) FROM {' . $table . '} WHERE ' . $column . ' REGEXP :re';
  $count = $database->query($sql, [':re' => $pattern])->fetchField();
  echo $label, ' 含旧域名的行数=', (string) $count, "\n";
}

$settings_file = DRUPAL_ROOT . '/sites/default/settings.php';
if (is_readable($settings_file)) {
  $text = file_get_contents($settings_file);
  if (is_string($text) && host_mentioned($text, $old)) {
    echo "settings.php 文本中仍有旧域名。文件末尾的迁移块已写入新域名；前面的旧 trusted_host_patterns 会被后面的赋值覆盖。\n";
  }
}
PHP
  out=$(mktemp)
  err=$(mktemp)
  set +e
  OLD_HOST="$OLD_HOST" NEW_HOST="$DOMAIN_LC" "${DRUSH[@]}" php:script "$php" >"$out" 2>"$err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    warn "扫描旧域名时出错。验收继续，整体不因此单独判失败。"
    print_captured_error "$err" "$out"
    printf '残留旧域名扫描失败，详见日志。\n' >>"$DOMAIN_SCAN_PATH"
  else
    redact_stream <"$out" >>"$DOMAIN_SCAN_PATH"
    if [[ -s "$err" ]]; then
      redact_file "$err" >>"$LOG"
    fi
  fi
  rm -f "$out" "$err"
  files_dir="$ROOT/web/sites/default/files"
  shown=0
  if [[ -d "$files_dir" ]]; then
    while IFS= read -r hit; do
      if grep -q -F -I -- "$OLD_HOST" "$hit"; then
        printf '生成文件仍含旧域名：%s\n' "${hit#"$files_dir"/}" >>"$DOMAIN_SCAN_PATH"
        shown=$((shown + 1))
        if [[ "$shown" -ge 20 ]]; then
          printf '生成文件还有更多匹配，已停止列举。\n' >>"$DOMAIN_SCAN_PATH"
          break
        fi
      fi
    done < <(find "$files_dir" -type f \( -name 'sitemap*.xml' -o -name 'robots.txt' \) -print)
  fi
  log_line "残留旧域名扫描已写入验收报告。"
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
  if [[ "$HTTP_CODE" == "400" ]]; then
    warn "首页返回 400。常见原因是 trusted_host_patterns 未生效，请确认 PHP-FPM 已读到新的 settings.php。"
  fi
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

导入后可以用旧站账号和原密码登录。install-restore.sh 生成的 admin 会被旧库覆盖。
Drupal 8 及以上的密码哈希不依赖 hash_salt。manifest 里若有该值，脚本已写回，用来保持一次性登录链接和部分 token。
trusted_host_patterns 已包含新域名。simple_sitemap.settings 的 base_url 会在该配置存在时改为新域名。
节点正文、菜单链接和其他用户内容里的绝对 URL 没有自动改写。验收报告列出仍含旧域名的配置名和若干字段计数。
邮件、Nginx、SSL、cron，以及未提交到 Git 的代码修改，需要导入后再处理。
切 DNS 前先用 hosts，或 curl -H "Host: 新域名" 测试。旧服务器至少再留几天。
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
  import_finalize_private_dest
  import_apply_settings
  import_extract_files
  import_extract_private
  import_verify_private_alignment
  import_chown_files
  import_update_database
  import_apply_domain_config
  import_rebuild_cache
  import_scan_leftover_domain
  import_disable_maintenance
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
  printf '%s\n' "${BACKUP%.sql.gz}-settings.php" >"$WORK/rollback-settings.txt"
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
  local ts host private_abs settings_src
  if [[ ! -d "$ROOT" ]]; then
    die "Drupal 根目录不存在：${ROOT}"
  fi
  init_drush || die "drush 不可用，没有修改站点。"
  assert_bootstrap || die "drush bootstrap 未成功，没有修改站点。"
  load_db_prefix || die "无法读取数据库前缀，没有修改站点。"
  ts=$(date '+%Y%m%d%H%M%S')
  PREMIGRATE_SQL="/root/xedc-prerollback-${ts}.sql.gz"
  PREMIGRATE_FILES="/root/xedc-prerollback-${ts}-files.tgz"
  SETTINGS_BACKUP="/root/xedc-prerollback-${ts}-settings.php"
  private_abs=$(current_private_dir || true)
  backup_database "$PREMIGRATE_SQL" || die "回滚前的数据库备份失败。没有删除现有数据。"
  if ! backup_files_tree "$PREMIGRATE_FILES" "$private_abs"; then
    die "回滚前的文件备份失败。数据库备份留在 ${PREMIGRATE_SQL}。没有删除现有数据。"
  fi
  if ! backup_settings_file "$SETTINGS_BACKUP"; then
    die "回滚前的 settings.php 备份失败。数据库备份留在 ${PREMIGRATE_SQL}。没有删除现有数据。"
  fi
  log_line "回滚前又做了一份当前数据备份：${PREMIGRATE_SQL}、${PREMIGRATE_FILES} 和 ${SETTINGS_BACKUP}"
  enable_maintenance rollback || die "无法打开维护模式。没有删除现有数据。"
  OVERWRITE_STARTED=1
  drop_tables || die "drush sql:drop 失败。当前库的备份在 ${PREMIGRATE_SQL}。"
  import_sql_gz "$BACKUP" || die "恢复备份失败。当前库的备份在 ${PREMIGRATE_SQL}。"
  rollback_restore_files || die "数据库已恢复为指定备份，但文件恢复失败。回滚前的文件在 ${PREMIGRATE_FILES}。"
  settings_src=$(tr -d '\r\n' <"$WORK/rollback-settings.txt")
  if [[ -f "$settings_src" ]]; then
    restore_settings_file "$settings_src" || die "数据库已恢复，但 settings.php 恢复失败。回滚前的 settings.php 在 ${SETTINGS_BACKUP}。"
  else
    warn "没有 ${settings_src}，这次不恢复 settings.php。"
  fi
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
