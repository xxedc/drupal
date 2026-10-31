#!/usr/bin/env bash
#
# install-restore.sh — 在 Ubuntu 24.04 或 26.04 上恢复本仓库的代码与配置结构。
#
# 恢复范围：Git 代码、Composer 锁定的 Drupal 11.4.11 与 contrib、自定义主题 xedc、
# 自定义模块、config/sync、仓库中的翻译文件。
# 不恢复：用户账号与内容、上传文件、数据库数据、sites/default/files 里的运行时文件。
#
# 已知风险
# 1. 仓库里提交的 config/sync 与原站点当时的实际运行配置可能不一致
#    （未导出的界面改动、settings.php 里的 $config 覆盖、服务器上的临时配置）。
#    本脚本在空库上执行 drush site:install --existing-config，直接采用 config/sync。
#    结果以仓库中的 config/sync 为准，不保证与原生产环境完全一致。
# 2. 安装前会把本站自己的绝对地址改成本次域名，只处理 git clone 出来的 config/sync，包括：
#    simple_sitemap 的 base_url、Metatag 里指向本站的 http(s) URL（含序列化字段）、
#    @旧域名 的站点邮箱，以及与旧域名完全相同的主机名（如 smtp_client_hostname）。
#    不替换子域上的外部统计（例如 Matomo）、SMTP 服务器、外部邮箱、Drupal.org、
#    oEmbed 和搜索引擎 IndexNow。这些会在日志里列出。脚本不打印配置中的口令。
#    替换后校验全部 YAML 仍可解析；解析失败则恢复原文件并报错，不保留半截改写。
# 3. 每次运行都会重新 git clone 指定分支的最新提交。目标目录已存在时，
#    先整目录改名备份，再克隆。备份里可能有旧的上传文件，新站点不会使用它们。
# 4. 已有真实站点只看 node_field_data 行数大于 0，或存在 uid>1 的用户。
#    不能仅因库里已有表就跳过后续步骤。未传入 --reinstall 时不改动已有数据。
#    --reinstall 会删除并重建数据库；库里已有真实内容时还必须同时传入 --yes。
# 5. 始终使用 composer install 安装 composer.lock 中锁定的版本，不执行 composer update。
# 6. 空库安装使用 drush site:install --existing-config，不再把 standard 当作 profile 参数，
#    也不再分阶段 partial 导入或手工创建内容类型/词汇。
#    clone 之后、域名替换之前，只在工作副本上按顶层 id 做配置自愈，不改仓库里的 config/sync。
#    自愈后仍有无法处理的问题则预检失败：打印明细，不执行 site:install，但继续写凭据。
#    site:install 无论成败都再执行 drush cim。日志在 /var/log/xedc-restore-install.log。
#    每次 cim 前等待并必要时清除 config_importer 锁，核对同步目录可读，并检查导入计划。
#    cim 成功必须看到成功原文，且不能出现配置锁警告；不能只看退出码。
#    判定成功后继续多轮 cim，直到差异不再下降。失败时状态写失败并附原因，绝不写成成功。
#    回写差异只改本次 clone 的工作副本。本脚本不执行 git commit 或 git push。
#
# 用法：
#   sudo ./install-restore.sh example.com
#   sudo ./install-restore.sh example.com --ssl --email admin@example.com
#   sudo ./install-restore.sh example.com --yes --reinstall

set -euo pipefail

RESTORE_SCRIPT_COPY="${RESTORE_SCRIPT_COPY:-}"

if [[ -z "${RESTORE_REEXEC:-}" ]]; then
  _src=$(readlink -f "$0")
  _copy=$(mktemp /tmp/install-restore.XXXXXX.sh)
  cp "$_src" "$_copy"
  export RESTORE_REEXEC=1
  export RESTORE_SCRIPT_COPY="$_copy"
  cd /
  exec bash "$_copy" "$@"
fi

cd /

WEB_USER=www-data
APP_ROOT="${APP_ROOT:-/var/www/drupal}"
GIT_REPO="${GIT_REPO:-https://github.com/xxedc/drupal.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"
DOMAIN="${DOMAIN:-}"
DB_NAME="${DB_NAME:-drupal}"
DB_USER="${DB_USER:-drupal}"
DB_PASS="${DB_PASS:-}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DRUPAL_ADMIN_USER="${DRUPAL_ADMIN_USER:-admin}"
DRUPAL_ADMIN_PASS="${DRUPAL_ADMIN_PASS:-}"
DRUPAL_SITE_NAME="${DRUPAL_SITE_NAME:-}"
DRUPAL_SITE_MAIL="${DRUPAL_SITE_MAIL:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
LOCAL_SETTINGS_SRC="${LOCAL_SETTINGS_SRC:-/root/xedc-settings.local.php}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-/root/xedc-restore-credentials.txt}"
ENABLE_SSL=0
WITH_WWW=1
REINSTALL=0
ASSUME_YES=0
SSL_FAILED=0
IMPORT_FAILED=0
CREDENTIALS_WRITTEN=0
CIM_LOG=""
DID_INSTALL=0
PUBLIC_BASE=""
HASH_SALT=""
SQL_BIN=""
DB_SERVICE=""
DRUSH_BIN=""
SERVER_NAMES=""
BACKUP_PATH=""
SITE_HAS_CONTENT=0
PREFLIGHT_FAILED=0
PREFLIGHT_STATUS="未执行"
PREFLIGHT_ERRORS=""
REWRITE_FAILED=0
URL_REWRITE_STATUS="未执行"
CONFIG_IMPORT_STATUS="未执行"
CONFIG_DIFF_COUNT="未统计"
CONFIG_DIFF_NAMES=""
INSTALL_LOG="${INSTALL_LOG:-/var/log/xedc-restore-install.log}"
INSTALL_LOG_READY=0
STRAY_CONFIG_DIR=""
SELF_HEAL_RECORD=""
SELF_HEAL_UNHANDLED=""
ACCEPTANCE_SUMMARY=""
ACCEPTANCE_DONE=0
ACCEPTANCE_PRINTED=0
ACCEPTANCE_READY=0
FIRST_ERROR_TEXT=""
FIRST_ERROR_BLOCK=""
LAST_DRUSH_LOG=""
PARSED_ENTITY_TYPE=""
PARSED_ENTITY_ID=""
CIM_JUDGED_OK=0
OVERALL_STATUS="未执行"
FAIL_REASON=""
PLAN_DETAIL=""
HTTP_ERROR_EXCERPT=""
NODE_TYPE_EXPECTED="未统计"
NODE_TYPE_ACTUAL="未统计"
SYNC_LIST_COUNT=0

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

note_log() {
  log "$*"
  if [[ "${INSTALL_LOG_READY:-0}" -eq 1 && -n "${INSTALL_LOG:-}" && -f "$INSTALL_LOG" ]]; then
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$INSTALL_LOG"
  fi
}

warn() {
  printf '\n[%s] 警告: %s\n' "$(date '+%F %T')" "$*" >&2
}

die() {
  printf '\n[%s] 错误: %s\n' "$(date '+%F %T')" "$*" >&2
  exit 1
}

trap 'rc=$?; printf "\n[错误] 第 %s 行失败（状态 %s）：%s\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; if [[ -n "${BACKUP_PATH:-}" ]]; then printf "旧目录备份仍在：%s\n" "$BACKUP_PATH" >&2; fi' ERR
trap 'write_acceptance || true; write_credentials || true; print_acceptance_line || true' EXIT

usage() {
  cat <<'EOF'
用法：sudo ./install-restore.sh [域名] [选项]

在 Ubuntu 24.04 或 26.04 上安装运行环境，克隆 https://github.com/xxedc/drupal 的最新代码，
按 composer.lock 安装 Drupal 11.4.11，构建 xedc 主题，并用 config/sync 执行
drush site:install --existing-config。不再先安装 standard 再分阶段导入。
导入前会在工作副本上自愈 config/sync，再把属于本站的绝对地址改成本次域名。
安装前预检配置。预检失败会写明错误、阻止 site:install，并继续写凭据文件。
site:install 无论成败都会再执行 drush cim。cim 前会核对锁、同步目录和导入计划。

选项：
  --domain 域名         站点域名，也可作为第一个位置参数
  --ssl, --certbot      使用 Certbot webroot 申请 Let's Encrypt 证书并启用 HTTPS
  --email 地址          Certbot 通知邮箱（默认 admin@域名）
  --no-www              不为 www 子域申请证书、写入 server_name
  --app-root 路径       代码目录，默认 /var/www/drupal
  --repo URL            Git 仓库，默认 https://github.com/xxedc/drupal.git
  --branch 名称         分支，默认 main
  --db-name 名称        数据库名，默认 drupal（仅允许字母、数字、下划线）
  --db-user 名称        数据库用户，默认 drupal
  --db-pass 口令        数据库口令；省略时自动生成
  --admin-user 名称     Drupal 管理员，默认 admin
  --admin-pass 口令     管理员口令；省略时仅在全新安装时自动生成
  --site-name 名称      安装时的站点名；省略时读取 config/sync/system.site.yml
  --site-mail 邮箱      站点邮箱；省略时使用 admin@域名
  --yes, -y             目标目录已存在时，确认将其整目录备份后重新克隆
  --reinstall           删除并重建数据库。若库中已有内容，还必须同时传入 --yes
  -h, --help            显示本说明

环境变量与同名选项等价：APP_ROOT、GIT_REPO、GIT_BRANCH、DOMAIN、DB_NAME、DB_USER、
DB_PASS、DRUPAL_ADMIN_USER、DRUPAL_ADMIN_PASS、DRUPAL_SITE_NAME、DRUPAL_SITE_MAIL、
CERTBOT_EMAIL、LOCAL_SETTINGS_SRC、CREDENTIALS_FILE。

每次运行都会重新克隆仓库，因此会拿到当时的最新代码、composer.lock、config/sync 和主题。
不执行 composer update。
EOF
}

random_secret() {
  local length="$1"
  local secret
  secret=$(php -r 'echo substr(str_replace(["+","/","="], "", base64_encode(random_bytes(96))), 0, (int) $argv[1]);' "$length")
  if [[ "${#secret}" -ne "$length" ]]; then
    die "无法生成随机口令。"
  fi
  printf '%s\n' "$secret"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请用 root 运行：sudo ./install-restore.sh <域名>"
  fi
}

check_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "此脚本只支持 Ubuntu。"
  fi
  case "${VERSION_ID:-}" in
    24.04|26.04)
      log "系统 ${PRETTY_NAME:-Ubuntu ${VERSION_ID}}，继续安装。"
      ;;
    *)
      warn "当前系统是 ${PRETTY_NAME:-unknown}。脚本针对 Ubuntu 24.04 和 26.04，将继续尝试安装依赖。"
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --ssl|--certbot)
        ENABLE_SSL=1
        shift
        ;;
      --no-www)
        WITH_WWW=0
        shift
        ;;
      --reinstall)
        REINSTALL=1
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --email)
        CERTBOT_EMAIL="${2:-}"
        shift 2
        ;;
      --app-root)
        APP_ROOT="${2:-}"
        shift 2
        ;;
      --repo)
        GIT_REPO="${2:-}"
        shift 2
        ;;
      --branch)
        GIT_BRANCH="${2:-}"
        shift 2
        ;;
      --db-name)
        DB_NAME="${2:-}"
        shift 2
        ;;
      --db-user)
        DB_USER="${2:-}"
        shift 2
        ;;
      --db-pass)
        DB_PASS="${2:-}"
        shift 2
        ;;
      --admin-user)
        DRUPAL_ADMIN_USER="${2:-}"
        shift 2
        ;;
      --admin-pass)
        DRUPAL_ADMIN_PASS="${2:-}"
        shift 2
        ;;
      --site-name)
        DRUPAL_SITE_NAME="${2:-}"
        shift 2
        ;;
      --site-mail)
        DRUPAL_SITE_MAIL="${2:-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "未知参数：$1（可用 --help 查看）"
        ;;
      *)
        if [[ -z "$DOMAIN" ]]; then
          DOMAIN="$1"
          shift
        else
          die "多余的参数：$1"
        fi
        ;;
    esac
  done
}

validate_inputs() {
  if [[ -z "$DOMAIN" ]]; then
    DOMAIN=$(hostname -f 2>/dev/null || hostname)
    warn "未传入域名，暂时使用 ${DOMAIN}。对外提供访问时请传入真实域名。"
  fi
  if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
    die "域名格式无效：${DOMAIN}"
  fi
  if [[ ! "$APP_ROOT" =~ ^/[A-Za-z0-9._/-]+$ || "$APP_ROOT" == */ || "$APP_ROOT" == *..* ]]; then
    die "APP_ROOT 必须是不含空格和 .. 的绝对路径。"
  fi
  case "$APP_ROOT" in
    /|/bin|/sbin|/etc|/usr|/usr/*|/var|/root|/home|/tmp|/var/www|/var/log|/var/lib)
      die "APP_ROOT 不能是系统目录：${APP_ROOT}"
      ;;
  esac
  if [[ ! "$DB_NAME" =~ ^[A-Za-z0-9_]+$ || ! "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
    die "数据库名和用户只能包含字母、数字和下划线。"
  fi
  if [[ ! "$DB_PORT" =~ ^[0-9]+$ ]]; then
    die "数据库端口无效。"
  fi
  if [[ "$DB_HOST" != "localhost" && "$DB_HOST" != "127.0.0.1" ]]; then
    die "此脚本只创建本机 MariaDB 账号，DB_HOST 请使用 localhost。"
  fi
  if [[ ! "$DRUPAL_ADMIN_USER" =~ ^[A-Za-z0-9._@-]{1,60}$ ]]; then
    die "管理员用户名包含不支持的字符。"
  fi
  if [[ ! "$GIT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    die "分支名无效。"
  fi
  if [[ -n "$CERTBOT_EMAIL" && ! "$CERTBOT_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
    die "Certbot 邮箱格式无效。"
  fi

  SERVER_NAMES="$DOMAIN"
  if [[ "$WITH_WWW" -eq 1 && "$DOMAIN" != www.* ]]; then
    SERVER_NAMES="${DOMAIN} www.${DOMAIN}"
  fi
  if [[ -z "$DRUPAL_SITE_MAIL" ]]; then
    DRUPAL_SITE_MAIL="admin@${DOMAIN}"
  fi
  if [[ "$ENABLE_SSL" -eq 1 && -z "$CERTBOT_EMAIL" ]]; then
    CERTBOT_EMAIL="admin@${DOMAIN}"
    log "未提供 --email，Certbot 将使用 ${CERTBOT_EMAIL}。"
  fi
}

regex_host() {
  local escaped
  escaped=$(printf '%s' "$1" | sed -e 's/[.[\*^$()+?{|\\]/\\&/g')
  printf '^%s$\n' "$escaped"
}

apt_get_install() {
  if ! apt-get install -y "$@"; then
    die "apt-get install 失败。"
  fi
}

apt_get_update() {
  local attempt source_file switched=0
  for attempt in 1 2 3; do
    if apt-get update; then
      return 0
    fi
    warn "apt-get update 失败（第 ${attempt}/3 次）。清空 /var/lib/apt/lists 后重试。"
    rm -rf /var/lib/apt/lists/*
    mkdir -p /var/lib/apt/lists/partial
    if [[ "$attempt" -lt 3 ]]; then
      log "等待 20 秒后再次执行 apt-get update。"
      sleep 20
    fi
  done
  shopt -s nullglob
  for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [[ -f "$source_file" ]] && grep -q 'ec2.archive.ubuntu.com' "$source_file"; then
      sed -i 's/ec2\.archive\.ubuntu\.com/archive.ubuntu.com/g' "$source_file"
      note_log "已把 ${source_file} 里的 ec2.archive.ubuntu.com 改为 archive.ubuntu.com。"
      switched=1
    fi
  done
  shopt -u nullglob
  if [[ "$switched" -eq 1 ]]; then
    rm -rf /var/lib/apt/lists/*
    mkdir -p /var/lib/apt/lists/partial
    note_log "等待 20 秒后，改用 archive.ubuntu.com 再执行一次 apt-get update。"
    sleep 20
    if apt-get update; then
      return 0
    fi
    warn "改用 archive.ubuntu.com 后 apt-get update 仍失败。"
  fi
  note_log "apt-get update 多次失败。索引不完整时仍继续安装；只有随后的 apt-get install 失败才中止。"
  return 1
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "安装基础软件包与 PHP 8.5。"
  apt_get_update || warn "apt-get update 未完全成功，继续尝试安装软件包。"
  apt_get_install \
    ca-certificates \
    curl \
    gnupg \
    git \
    unzip \
    openssl \
    software-properties-common \
    apt-transport-https
  if ! apt-cache show php8.5-cli >/dev/null 2>&1; then
    log "系统源没有 PHP 8.5，添加 ondrej/php。"
    add-apt-repository -y ppa:ondrej/php
    apt_get_update || warn "添加 PPA 后 apt-get update 未完全成功，继续尝试安装 PHP。"
  else
    log "软件源已提供 PHP 8.5，不再重复添加 PPA。"
  fi
  if ! apt-cache show php8.5-cli >/dev/null 2>&1; then
    die "Ubuntu ${VERSION_ID:-unknown} 的软件源中没有 php8.5-cli。请确认 ondrej/php 已支持该版本。"
  fi
  apt_get_install \
    nginx \
    mariadb-server \
    php8.5-cli \
    php8.5-fpm \
    php8.5-mysql \
    php8.5-gd \
    php8.5-mbstring \
    php8.5-xml \
    php8.5-curl \
    php8.5-zip \
    php8.5-intl \
    php8.5-bcmath \
    php8.5-apcu \
    php8.5-readline

  if [[ -x /usr/bin/php8.5 ]]; then
    update-alternatives --install /usr/bin/php php /usr/bin/php8.5 85 >/dev/null
    update-alternatives --set php /usr/bin/php8.5 >/dev/null
  fi
  if ! php -r 'exit(PHP_VERSION_ID >= 80500 && PHP_VERSION_ID < 80600 ? 0 : 1);'; then
    die "PHP 8.5 未成为默认 php 命令。当前：$(php -v | head -n 1)"
  fi
  log "PHP $(php -r 'echo PHP_VERSION;') 已就绪。OPcache 随 PHP 8.5 提供。"

  install_node
  install_composer

  if command -v mariadb >/dev/null 2>&1; then
    SQL_BIN=mariadb
  else
    SQL_BIN=mysql
  fi
  if systemctl cat mariadb.service >/dev/null 2>&1; then
    DB_SERVICE=mariadb
  else
    DB_SERVICE=mysql
  fi
}

install_node() {
  local major=0
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    major=$(node -p 'Number(process.versions.node.split(".")[0])')
  fi
  if [[ "$major" -ge 18 ]]; then
    log "已存在 Node.js $(node -v) 与 npm $(npm -v)，跳过安装。"
    return 0
  fi
  log "安装 Node.js 22。"
  if ! curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
    warn "NodeSource 安装脚本失败，改用 Ubuntu 软件源中的 Node.js。"
    apt-get install -y nodejs npm
  else
    apt-get install -y nodejs
  fi
  major=$(node -p 'Number(process.versions.node.split(".")[0])')
  if [[ "$major" -lt 18 ]]; then
    die "Node.js 版本低于 18。"
  fi
  log "Node.js $(node -v)，npm $(npm -v)。"
}

install_composer() {
  if command -v composer >/dev/null 2>&1; then
    log "已存在 $(composer --version | head -n 1)，跳过 Composer 安装。"
    return 0
  fi
  log "安装 Composer。"
  local installer
  installer=$(mktemp /tmp/composer-setup.XXXXXX.php)
  curl -fsSL https://getcomposer.org/installer -o "$installer"
  php "$installer" --install-dir=/usr/local/bin --filename=composer
  rm -f "$installer"
  command -v composer >/dev/null 2>&1 || die "Composer 安装失败。"
}

configure_php() {
  log "写入 PHP 8.5 配置。"
  local fpm_ini=/etc/php/8.5/fpm/conf.d/99-xedc.ini
  local cli_ini=/etc/php/8.5/cli/conf.d/99-xedc.ini
  cat >"$fpm_ini" <<'EOF'
; Managed by install-restore.sh
expose_php = Off
memory_limit = 512M
upload_max_filesize = 200M
post_max_size = 220M
max_execution_time = 300
max_input_time = 300
max_input_vars = 10000
date.timezone = Asia/Shanghai
cgi.fix_pathinfo = 0
opcache.enable = 1
opcache.memory_consumption = 192
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0
realpath_cache_size = 4096K
realpath_cache_ttl = 600
EOF
  cat >"$cli_ini" <<'EOF'
; Managed by install-restore.sh
expose_php = Off
memory_limit = 1024M
max_execution_time = 0
max_input_vars = 10000
date.timezone = Asia/Shanghai
opcache.enable_cli = 0
EOF

  local pool=/etc/php/8.5/fpm/pool.d/www.conf
  if [[ -f "$pool" ]]; then
    sed -i \
      -e 's/^user = .*/user = www-data/' \
      -e 's/^group = .*/group = www-data/' \
      -e 's|^listen = .*|listen = /run/php/php8.5-fpm.sock|' \
      -e 's/^;*listen.owner = .*/listen.owner = www-data/' \
      -e 's/^;*listen.group = .*/listen.group = www-data/' \
      "$pool"
  fi
  systemctl enable php8.5-fpm
  systemctl restart php8.5-fpm
}

configure_mariadb() {
  log "配置 MariaDB（utf8mb4，READ COMMITTED）并启动服务。"
  cat >/etc/mysql/mariadb.conf.d/99-xedc.cnf <<'EOF'
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
transaction-isolation = READ-COMMITTED
innodb_file_per_table = 1
EOF
  systemctl enable "$DB_SERVICE"
  systemctl restart "$DB_SERVICE"
}

disk_warning() {
  local parent avail_kb
  parent=$(dirname "$APP_ROOT")
  if [[ ! -d "$parent" ]]; then
    parent=/
  fi
  avail_kb=$(df -Pk "$parent" | awk 'NR==2 {print $4}')
  if [[ "${avail_kb:-0}" -lt 2097152 ]]; then
    warn "可用磁盘不足 2GB。完整克隆、Composer 与主题构建可能失败；旧目录备份还会额外占用空间。"
  fi
}

sql_scalar_required() {
  local result
  if ! result=$("$SQL_BIN" --protocol=socket --batch --skip-column-names --user=root -e "$1"); then
    die "无法以系统 root 通过本地套接字连接 MariaDB。"
  fi
  result=${result//$'\n'/}
  if [[ ! "$result" =~ ^[0-9]+$ ]]; then
    die "MariaDB 返回了无法识别的结果。"
  fi
  printf '%s\n' "$result"
}

assert_database_safe() {
  local exists node_table user_table node_rows extra_users any_tables
  exists=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'")
  if [[ "$exists" -eq 0 ]]; then
    log "数据库 ${DB_NAME} 尚不存在，稍后会创建空库。"
    return 0
  fi
  node_table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='node_field_data'")
  user_table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='users_field_data'")
  node_rows=0
  extra_users=0
  if [[ "$node_table" -ge 1 ]]; then
    node_rows=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.node_field_data")
  fi
  if [[ "$user_table" -ge 1 ]]; then
    extra_users=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.users_field_data WHERE uid>1")
  fi
  if [[ "$node_rows" -gt 0 || "$extra_users" -gt 0 ]]; then
    if [[ "$REINSTALL" -eq 1 ]]; then
      if [[ "$ASSUME_YES" -ne 1 ]]; then
        die "数据库 ${DB_NAME} 已有真实站点（node_field_data ${node_rows} 行，uid>1 的用户 ${extra_users} 个）。删除该库并重新安装必须同时传入 --reinstall --yes。"
      fi
      warn "将按 --reinstall --yes 删除数据库 ${DB_NAME} 中的全部数据。"
      return 0
    fi
    SITE_HAS_CONTENT=1
    log "数据库 ${DB_NAME} 已有真实站点（node_field_data ${node_rows} 行，uid>1 的用户 ${extra_users} 个）。未传入 --reinstall，跳过安装，不删除数据库，也不导入配置。"
    return 0
  fi

  if [[ "$user_table" -eq 0 ]]; then
    any_tables=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")
    if [[ "$any_tables" -gt 0 && "$REINSTALL" -ne 1 ]]; then
      die "数据库 ${DB_NAME} 非空，但不是可识别的 Drupal 站点。请换一个空库，或同时传入 --reinstall --yes 以删除该库。"
    fi
    if [[ "$any_tables" -gt 0 && "$ASSUME_YES" -ne 1 ]]; then
      die "将删除非空数据库 ${DB_NAME}。请同时传入 --reinstall --yes。"
    fi
    return 0
  fi

  if [[ "$REINSTALL" -eq 1 ]]; then
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      die "重新安装会删除数据库 ${DB_NAME}。请同时传入 --yes。"
    fi
    warn "数据库 ${DB_NAME} 将按 --reinstall 删除并重建。"
  else
    log "数据库 ${DB_NAME} 已有 Drupal 表，但 node_field_data 为 0 且没有 uid>1 的用户。这不是已有真实站点，不会因此跳过后续导入。"
  fi
}

database_has_no_real_content() {
  local exists node_table user_table node_rows extra_users
  if [[ -z "${SQL_BIN:-}" || -z "${DB_NAME:-}" ]]; then
    warn "无法确认数据库内容，拒绝删除配置锁。"
    return 1
  fi
  exists=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'")
  if [[ "$exists" -eq 0 ]]; then
    return 0
  fi
  node_table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='node_field_data'")
  user_table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='users_field_data'")
  node_rows=0
  extra_users=0
  if [[ "$node_table" -ge 1 ]]; then
    node_rows=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.node_field_data")
  fi
  if [[ "$user_table" -ge 1 ]]; then
    extra_users=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.users_field_data WHERE uid>1")
  fi
  if [[ "$node_rows" -eq 0 && "$extra_users" -eq 0 ]]; then
    return 0
  fi
  warn "数据库已有真实站点内容：node_field_data ${node_rows} 行，uid>1 的用户 ${extra_users} 个。"
  return 1
}

clone_repository() {
  disk_warning
  mkdir -p "$(dirname "$APP_ROOT")"
  if [[ -e "$APP_ROOT" ]]; then
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      die "目录 ${APP_ROOT} 已存在。脚本会把该目录整份改名备份后再克隆最新代码。确认后请追加 --yes。"
    fi
    BACKUP_PATH="${APP_ROOT}.bak.$(date +%Y%m%d%H%M%S)"
    if [[ -e "$BACKUP_PATH" ]]; then
      die "备份路径已存在：${BACKUP_PATH}"
    fi
    log "将现有目录移动到 ${BACKUP_PATH}。新站点不会取用其中的上传文件或旧 settings.php。"
    mv "$APP_ROOT" "$BACKUP_PATH"
  fi

  log "克隆 ${GIT_REPO} 分支 ${GIT_BRANCH} 的最新提交到 ${APP_ROOT}。"
  GIT_TERMINAL_PROMPT=0 git clone --branch "$GIT_BRANCH" "$GIT_REPO" "$APP_ROOT"
  log "当前提交：$(git -C "$APP_ROOT" log -1 --pretty='%h %s')"

  if [[ -f "$APP_ROOT/web/sites/default/settings.php" ]]; then
    rm -f "$APP_ROOT/web/sites/default/settings.php"
    log "已删除仓库中的 settings.php，稍后会生成新的 hash_salt 与数据库配置。"
  fi
  [[ -f "$APP_ROOT/composer.lock" ]] || die "克隆结果缺少 composer.lock，已中止。"
  [[ -f "$APP_ROOT/config/sync/system.site.yml" ]] || die "克隆结果缺少 config/sync/system.site.yml，已中止。"
}

verify_locked_core() {
  local locked installed
  locked=$(php -r '
    $lock = json_decode(file_get_contents($argv[1]), true);
    if (!is_array($lock) || empty($lock["packages"])) { exit(2); }
    foreach ($lock["packages"] as $package) {
      if (($package["name"] ?? "") === "drupal/core") {
        echo $package["version"] ?? "";
        exit(0);
      }
    }
    exit(3);
  ' "$APP_ROOT/composer.lock")
  if [[ "$locked" != "11.4.11" ]]; then
    die "composer.lock 中的 drupal/core 是 ${locked:-未知}，此脚本要求 11.4.11。不会执行 composer update。"
  fi
  if [[ -f "$APP_ROOT/web/core/lib/Drupal.php" ]]; then
    installed=$(sed -n "s/^[[:space:]]*const VERSION = '\\([^']*\\)';/\\1/p" "$APP_ROOT/web/core/lib/Drupal.php")
    if [[ "$installed" != "11.4.11" ]]; then
      die "已安装的 Drupal core 是 ${installed:-未知}，与锁定的 11.4.11 不一致。"
    fi
  fi
  log "已确认 Drupal core 锁定为 11.4.11。"
}

composer_install() {
  log "执行 composer install --no-dev（只使用 composer.lock，不更新依赖）。"
  verify_locked_core
  (
    cd "$APP_ROOT"
    COMPOSER_ALLOW_SUPERUSER=1 \
      COMPOSER_MEMORY_LIMIT=-1 \
      COMPOSER_NO_INTERACTION=1 \
      composer install --no-dev --no-interaction --prefer-dist --no-progress
  )
  verify_locked_core
  DRUSH_BIN="$APP_ROOT/vendor/bin/drush"
  [[ -f "$DRUSH_BIN" ]] || die "composer install 未提供 vendor/bin/drush。"
}

build_theme() {
  local theme="$APP_ROOT/web/themes/custom/xedc"
  if [[ ! -f "$theme/package.json" ]]; then
    log "未找到 ${theme}/package.json，跳过主题构建。"
    return 0
  fi
  log "构建自定义主题 xedc（npm install && npm run build）。"
  (
    cd "$theme"
    npm install
    npm run build
  )
}

apply_database() {
  log "创建或更新数据库 ${DB_NAME} 与用户 ${DB_USER}。"
  if [[ -z "$DB_PASS" ]]; then
    DB_PASS=$(random_secret 32)
  fi
  local sql_file
  sql_file=$(mktemp /tmp/xedc-db.XXXXXX.sql)
  chmod 600 "$sql_file"
  DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASS="$DB_PASS" REINSTALL="$REINSTALL" SQL_FILE="$sql_file" php <<'PHP'
<?php
$name = getenv('DB_NAME');
$user = getenv('DB_USER');
$pass = getenv('DB_PASS');
if (!preg_match('/^[A-Za-z0-9_]+$/', $name) || !preg_match('/^[A-Za-z0-9_]+$/', $user)) {
  fwrite(STDERR, "数据库名或用户无效。\n");
  exit(1);
}
$passSql = str_replace(["\\", "'"], ["\\\\", "\\'"], $pass);
$sql = '';
if (getenv('REINSTALL') === '1') {
  $sql .= "DROP DATABASE IF EXISTS `{$name}`;\n";
}
$sql .= "CREATE DATABASE IF NOT EXISTS `{$name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n";
foreach (['localhost', '127.0.0.1'] as $host) {
  $sql .= "CREATE USER IF NOT EXISTS '{$user}'@'{$host}' IDENTIFIED BY '{$passSql}';\n";
  $sql .= "ALTER USER '{$user}'@'{$host}' IDENTIFIED BY '{$passSql}';\n";
  $sql .= "GRANT ALL PRIVILEGES ON `{$name}`.* TO '{$user}'@'{$host}';\n";
}
$sql .= "FLUSH PRIVILEGES;\n";
if (file_put_contents(getenv('SQL_FILE'), $sql) === false) {
  fwrite(STDERR, "无法写入数据库初始化语句。\n");
  exit(1);
}
PHP
  "$SQL_BIN" --protocol=socket --user=root <"$sql_file"
  rm -f "$sql_file"
}

site_installed() {
  local users_table
  users_table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='users_field_data'")
  [[ "$users_table" -ge 1 ]]
}

trusted_patterns() {
  regex_host "$DOMAIN"
  if [[ "$WITH_WWW" -eq 1 && "$DOMAIN" != www.* ]]; then
    regex_host "www.${DOMAIN}"
  fi
  printf '%s\n' '^localhost$'
  local extra
  for extra in "$(hostname -s 2>/dev/null || true)" "$(hostname -f 2>/dev/null || true)"; do
    if [[ -n "$extra" && "$extra" != "$DOMAIN" && "$extra" != "www.${DOMAIN}" && "$extra" != "localhost" ]]; then
      if [[ "$extra" =~ ^[A-Za-z0-9.-]+$ ]]; then
        regex_host "$extra"
      fi
    fi
  done
}

write_settings() {
  local template="$APP_ROOT/web/sites/default/default.settings.php"
  local dest="$APP_ROOT/web/sites/default/settings.php"
  [[ -f "$template" ]] || die "缺少 default.settings.php，Composer scaffold 可能未执行。"
  if [[ -z "$HASH_SALT" ]]; then
    HASH_SALT=$(random_secret 64)
  fi
  if [[ -z "$DRUPAL_SITE_NAME" ]]; then
    DRUPAL_SITE_NAME=$(php -r '
      foreach (file($argv[1]) as $line) {
        if (preg_match("/^name:\\s*(.+)\\s*$/", $line, $matches)) {
          echo trim($matches[1], " \"'\''");
          exit(0);
        }
      }
    ' "$APP_ROOT/config/sync/system.site.yml")
    DRUPAL_SITE_NAME="${DRUPAL_SITE_NAME:-Drupal}"
  fi
  install -d -o root -g "$WEB_USER" -m 755 "$APP_ROOT/web/sites/default"
  if [[ -f "$dest" ]]; then
    chmod u+w "$dest" || true
  fi
  SETTINGS_TEMPLATE="$template" \
    SETTINGS_DEST="$dest" \
    DB_NAME="$DB_NAME" \
    DB_USER="$DB_USER" \
    DB_PASS="$DB_PASS" \
    DB_HOST="$DB_HOST" \
    DB_PORT="$DB_PORT" \
    HASH_SALT="$HASH_SALT" \
    PRIVATE_PATH="$APP_ROOT/private" \
    TRUSTED_PATTERNS="$(trusted_patterns)" \
    php <<'PHP'
<?php
$template = getenv('SETTINGS_TEMPLATE');
$dest = getenv('SETTINGS_DEST');
$base = file_get_contents($template);
if ($base === false) {
  fwrite(STDERR, "无法读取 default.settings.php\n");
  exit(1);
}
$patterns = array_values(array_filter(preg_split('/\R/', (string) getenv('TRUSTED_PATTERNS'))));
$db = [
  'database' => getenv('DB_NAME'),
  'username' => getenv('DB_USER'),
  'password' => getenv('DB_PASS'),
  'prefix' => '',
  'host' => getenv('DB_HOST'),
  'port' => getenv('DB_PORT'),
  'isolation_level' => 'READ COMMITTED',
  'driver' => 'mysql',
  'namespace' => 'Drupal\\mysql\\Driver\\Database\\mysql',
  'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
];
$block = "\n// Generated by install-restore.sh. Replace this file on every restore; do not reuse a committed hash_salt.\n";
$block .= "\$databases['default']['default'] = " . var_export($db, true) . ";\n";
$block .= "\$settings['hash_salt'] = " . var_export((string) getenv('HASH_SALT'), true) . ";\n";
$block .= "\$settings['config_sync_directory'] = '../config/sync';\n";
$block .= "\$settings['trusted_host_patterns'] = " . var_export($patterns, true) . ";\n";
$block .= "\$settings['file_private_path'] = " . var_export((string) getenv('PRIVATE_PATH'), true) . ";\n";
$block .= "\$settings['file_temp_path'] = '/tmp';\n";
$block .= <<<'INCLUDE'

if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
INCLUDE;
$block .= "\n";
if (file_put_contents($dest, $base . $block) === false) {
  fwrite(STDERR, "无法写入 settings.php\n");
  exit(1);
}
PHP

  if [[ -f "$LOCAL_SETTINGS_SRC" ]]; then
    cp "$LOCAL_SETTINGS_SRC" "$APP_ROOT/web/sites/default/settings.local.php"
    log "已装入本地覆盖文件 ${LOCAL_SETTINGS_SRC}。"
  fi
}

prepare_directories() {
  install -d -o "$WEB_USER" -g "$WEB_USER" -m 775 "$APP_ROOT/web/sites/default/files"
  install -d -o "$WEB_USER" -g "$WEB_USER" -m 775 "$APP_ROOT/private"
}

fix_permissions() {
  local writable=0
  if [[ "${1:-}" == "writable-settings" ]]; then
    writable=1
  fi
  log "整理文件所有权。Web 用户 ${WEB_USER} 可写 sites/default/files 与 private。"
  chown -R root:"$WEB_USER" "$APP_ROOT"
  chmod -R u=rwX,g=rX,o= "$APP_ROOT"
  if [[ -d "$APP_ROOT/vendor/bin" ]]; then
    find "$APP_ROOT/vendor/bin" -type f -exec chmod 750 {} +
  fi
  chown -R "$WEB_USER":"$WEB_USER" "$APP_ROOT/web/sites/default/files" "$APP_ROOT/private"
  chmod -R u=rwX,g=rwX,o= "$APP_ROOT/web/sites/default/files" "$APP_ROOT/private"
  chown root:"$WEB_USER" "$APP_ROOT/web/sites/default" "$APP_ROOT/web/sites/default/settings.php"
  chmod 755 "$APP_ROOT/web/sites/default"
  if [[ "$writable" -eq 1 ]]; then
    chown "$WEB_USER":"$WEB_USER" "$APP_ROOT/web/sites/default" "$APP_ROOT/web/sites/default/settings.php"
    chmod 775 "$APP_ROOT/web/sites/default"
    chmod 660 "$APP_ROOT/web/sites/default/settings.php"
  else
    chmod 640 "$APP_ROOT/web/sites/default/settings.php"
  fi
  if [[ -f "$APP_ROOT/web/sites/default/settings.local.php" ]]; then
    chown root:"$WEB_USER" "$APP_ROOT/web/sites/default/settings.local.php"
    chmod 640 "$APP_ROOT/web/sites/default/settings.local.php"
  fi
}

write_nginx_snippets() {
  cat >/etc/nginx/snippets/xedc-security-headers.conf <<'EOF'
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
EOF

  cat >/etc/nginx/snippets/xedc-drupal.conf <<'EOF'
# Managed by install-restore.sh. Adapted from _server/nginx/conf.d/drupal.conf.
include /etc/nginx/snippets/xedc-security-headers.conf;
charset utf-8;
server_tokens off;
client_max_body_size 220m;
client_body_timeout 300s;
client_header_timeout 60s;
send_timeout 300s;

gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 5;
gzip_min_length 256;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml application/xml+rss image/svg+xml application/manifest+json;

location = /favicon.ico {
    log_not_found off;
    access_log off;
}
location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
}
location ^~ /.well-known/acme-challenge/ {
    allow all;
    default_type "text/plain";
}
location ~* ^/.well-known/ {
    allow all;
}
location ~ \..*/.*\.php$ { return 403; }
location ~ ^/sites/.*/private/ { return 403; }
location ~ ^/sites/[^/]+/files/.*\.php$ { deny all; }
location ~ (^|/)\. { return 403; }
location ~* /vendor/.*\.php$ { deny all; return 404; }

location / {
    try_files $uri /index.php?$query_string;
}
location @rewrite {
    rewrite ^ /index.php;
}

location ~ '\.php$|^/update.php' {
    include /etc/nginx/snippets/xedc-security-headers.conf;
    fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
    try_files $fastcgi_script_name =404;
    include fastcgi_params;
    fastcgi_param HTTP_PROXY "";
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_param QUERY_STRING $query_string;
    fastcgi_intercept_errors on;
    fastcgi_read_timeout 300s;
    fastcgi_send_timeout 300s;
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;
    fastcgi_pass unix:/run/php/php8.5-fpm.sock;
}

location ~ ^/sites/.*/files/styles/ {
    include /etc/nginx/snippets/xedc-security-headers.conf;
    try_files $uri @rewrite;
    expires 1y;
    add_header Cache-Control "public";
    log_not_found off;
}
location ~ ^(/[a-z\-]+)?/system/files/ {
    try_files $uri /index.php?$query_string;
}
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff2?)$ {
    include /etc/nginx/snippets/xedc-security-headers.conf;
    try_files $uri @rewrite;
    expires 1y;
    add_header Cache-Control "public";
    log_not_found off;
}
EOF
}

nginx_http2_modern() {
  local version
  version=$(nginx -v 2>&1 | sed -n 's|.*nginx/\([0-9.]*\).*|\1|p')
  php -r 'exit(version_compare($argv[1], "1.25.1", ">=") ? 0 : 1);' "$version"
}

write_nginx_site() {
  local mode="$1"
  local dest=/etc/nginx/sites-available/xedc.conf
  if [[ "$mode" == "https" ]]; then
    local listen443 listen4436 http2 ssl_extra cert key
    cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    if nginx_http2_modern; then
      listen443="listen 443 ssl;"
      listen4436="listen [::]:443 ssl;"
      http2="http2 on;"
    else
      listen443="listen 443 ssl http2;"
      listen4436="listen [::]:443 ssl http2;"
      http2=""
    fi
    if [[ -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
      ssl_extra="include /etc/letsencrypt/options-ssl-nginx.conf;"
    else
      ssl_extra="ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;"
    fi
    if [[ -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
      ssl_extra="${ssl_extra}
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
    fi
    cat >"$dest" <<EOF
# Managed by install-restore.sh
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAMES};
    location ^~ /.well-known/acme-challenge/ {
        root ${APP_ROOT}/web;
        default_type "text/plain";
        allow all;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    ${listen443}
    ${listen4436}
    ${http2}
    server_name ${SERVER_NAMES};
    root ${APP_ROOT}/web;
    index index.php;
    ssl_certificate ${cert};
    ssl_certificate_key ${key};
    ${ssl_extra}
    include /etc/nginx/snippets/xedc-drupal.conf;
}
EOF
  else
    cat >"$dest" <<EOF
# Managed by install-restore.sh
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAMES};
    root ${APP_ROOT}/web;
    index index.php;
    include /etc/nginx/snippets/xedc-drupal.conf;
}
EOF
  fi
  ln -sfn "$dest" /etc/nginx/sites-enabled/xedc.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx
  systemctl reload nginx
}

obtain_certificate() {
  local cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  if [[ "$ENABLE_SSL" -ne 1 ]]; then
    if [[ -f "$cert" ]]; then
      log "发现已有证书，继续启用 HTTPS。"
      return 0
    fi
    return 1
  fi
  log "安装 Certbot 并申请证书。请确认域名 DNS 已指向这台服务器，且 80 端口可从公网访问。"
  apt-get install -y certbot
  local -a domains=(-d "$DOMAIN")
  if [[ "$WITH_WWW" -eq 1 && "$DOMAIN" != www.* ]]; then
    domains+=(-d "www.${DOMAIN}")
  fi
  if ! certbot certonly \
    --webroot -w "$APP_ROOT/web" \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    --keep-until-expiring \
    --expand \
    "${domains[@]}"; then
    warn "Certbot 未成功。站点会先以 HTTP 提供服务。确认 DNS 与 80 端口后，可重新运行并加上 --ssl。"
    SSL_FAILED=1
    return 1
  fi
  systemctl enable certbot.timer >/dev/null 2>&1 || true
  systemctl start certbot.timer >/dev/null 2>&1 || true
  return 0
}

configure_nginx() {
  write_nginx_snippets
  write_nginx_site http
  if obtain_certificate; then
    write_nginx_site https
    PUBLIC_BASE="https://${DOMAIN}"
  else
    PUBLIC_BASE="http://${DOMAIN}"
  fi
  log "Nginx 已加载，站点地址：${PUBLIC_BASE}"
}

run_drush() {
  local rc=0
  local chunk
  chunk=$(mktemp /tmp/xedc-drush.XXXXXX.log)
  chmod 600 "$chunk" || true
  if [[ -n "${LAST_DRUSH_LOG:-}" && -f "$LAST_DRUSH_LOG" ]]; then
    rm -f "$LAST_DRUSH_LOG"
  fi
  LAST_DRUSH_LOG="$chunk"
  if [[ "${INSTALL_LOG_READY:-0}" -ne 1 ]]; then
    prepare_install_log || true
  fi
  set +e
  (
    cd "$APP_ROOT"
    runuser -u "$WEB_USER" -- env HOME=/tmp "$DRUSH_BIN" --root="$APP_ROOT/web" --uri="$PUBLIC_BASE" "$@"
  ) 2>&1 | tee -a "$INSTALL_LOG" "$chunk"
  rc=${PIPESTATUS[0]}
  set -e
  if [[ "$rc" -ne 0 ]]; then
    print_first_error "$chunk" || true
  fi
  return "$rc"
}

urlencode() {
  php -r 'echo rawurlencode($argv[1]);' "$1"
}

drupal_db_url() {
  local user pass name
  user=$(urlencode "$DB_USER")
  pass=$(urlencode "$DB_PASS")
  name=$(urlencode "$DB_NAME")
  printf 'mysql://%s:%s@%s:%s/%s\n' "$user" "$pass" "$DB_HOST" "$DB_PORT" "$name"
}

prepare_install_log() {
  if [[ "${INSTALL_LOG_READY:-0}" -eq 1 && -f "$INSTALL_LOG" ]]; then
    return 0
  fi
  if ! : >"$INSTALL_LOG"; then
    warn "无法写入 ${INSTALL_LOG}，改用临时日志。"
    INSTALL_LOG=$(mktemp /tmp/xedc-restore-install.XXXXXX.log)
    : >"$INSTALL_LOG"
  fi
  chmod 600 "$INSTALL_LOG" || true
  INSTALL_LOG_READY=1
  if [[ -n "${SELF_HEAL_RECORD:-}" ]]; then
    {
      printf '\n===== 自愈记录 =====\n'
      printf '%s\n' "$SELF_HEAL_RECORD"
    } >>"$INSTALL_LOG"
  fi
}

read_site_uuid() {
  php -r '
    foreach (file($argv[1]) as $line) {
      if (preg_match("/^uuid:\\s*([0-9a-fA-F-]+)/", $line, $matches)) {
        echo $matches[1];
        exit(0);
      }
    }
    exit(1);
  ' "$APP_ROOT/config/sync/system.site.yml"
}

settings_config_sync_value() {
  local settings="$1"
  SETTINGS_FILE="$settings" php <<'PHP'
<?php
$file = getenv('SETTINGS_FILE');
$text = file_get_contents($file);
if ($text === false) {
    exit(1);
}
if (!preg_match('/\$settings\s*\[\s*[\'"]config_sync_directory[\'"]\s*\]\s*=\s*[\'"]([^\'"]+)[\'"]\s*;/', $text, $matches)) {
    exit(2);
}
echo $matches[1];
PHP
}

capture_stray_config_dir() {
  local settings current resolved
  settings="$APP_ROOT/web/sites/default/settings.php"
  STRAY_CONFIG_DIR=""
  if [[ ! -f "$settings" ]]; then
    return 0
  fi
  if ! current=$(settings_config_sync_value "$settings"); then
    return 0
  fi
  if [[ "$current" == "../config/sync" || "$current" == "$APP_ROOT/config/sync" ]]; then
    return 0
  fi
  if [[ "$current" == /* ]]; then
    resolved="$current"
  else
    resolved="$APP_ROOT/web/$current"
  fi
  case "$resolved" in
    "$APP_ROOT/web/sites/default/files"/config_*)
      STRAY_CONFIG_DIR="$resolved"
      log "drush 将 config_sync_directory 写到了 ${current}。稍后改回 ../config/sync，并删除该目录。"
      ;;
    *)
      warn "config_sync_directory 当前是 ${current}，不是 ../config/sync。"
      ;;
  esac
}

remove_stray_config_dir() {
  local stray files_root resolved
  stray="${STRAY_CONFIG_DIR:-}"
  STRAY_CONFIG_DIR=""
  if [[ -z "$stray" ]]; then
    return 0
  fi
  if [[ "$(basename "$stray")" == "sync" ]]; then
    stray=$(dirname "$stray")
  fi
  files_root=$(php -r 'echo realpath($argv[1]) ?: "";' "$APP_ROOT/web/sites/default/files")
  resolved=$(php -r 'echo realpath($argv[1]) ?: "";' "$stray")
  if [[ -z "$files_root" || -z "$resolved" ]]; then
    warn "未删除多余配置目录（路径不存在）：${stray}"
    return 0
  fi
  if [[ "$(dirname "$resolved")" != "$files_root" || "$(basename "$resolved")" != config_* ]]; then
    warn "拒绝删除不在 sites/default/files/config_* 下的路径：${resolved}"
    return 0
  fi
  if [[ -L "$resolved" ]]; then
    warn "多余配置目录是符号链接，不删除：${resolved}"
    return 0
  fi
  rm -rf "$resolved"
  log "已删除多余配置目录 ${resolved}。"
}

ensure_config_sync_directory() {
  local settings current
  settings="$APP_ROOT/web/sites/default/settings.php"
  if [[ ! -f "$settings" ]]; then
    warn "没有 settings.php，无法确认 config_sync_directory。"
    return 0
  fi
  remove_stray_config_dir
  if ! SETTINGS_FILE="$settings" php <<'PHP'
<?php
$file = getenv('SETTINGS_FILE');
$text = file_get_contents($file);
if ($text === false) {
    fwrite(STDERR, "无法读取 settings.php\n");
    exit(1);
}
$line = "\$settings['config_sync_directory'] = '../config/sync';";
$count = 0;
$updated = preg_replace(
    '/\$settings\s*\[\s*[\'"]config_sync_directory[\'"]\s*\]\s*=\s*[\'"][^\'"]*[\'"]\s*;/',
    $line,
    $text,
    1,
    $count
);
if (!is_string($updated) || $count < 1) {
    $updated = rtrim((string) $text) . "\n" . $line . "\n";
}
if (file_put_contents($file, $updated) === false) {
    fwrite(STDERR, "无法写回 settings.php\n");
    exit(1);
}
PHP
  then
    warn "未能把 config_sync_directory 写成 ../config/sync。"
    return 0
  fi
  if ! current=$(settings_config_sync_value "$settings"); then
    warn "写回后仍无法读取 config_sync_directory。"
    return 0
  fi
  if [[ "$current" == "../config/sync" ]]; then
    log "config_sync_directory 已指向 ../config/sync。"
    return 0
  fi
  warn "config_sync_directory 当前是 ${current}，不是 ../config/sync。"
  return 0
}

print_first_error() {
  local src="${1:-${LAST_DRUSH_LOG:-}}"
  local text=""
  if [[ -z "$src" || ! -f "$src" ]]; then
    src="${INSTALL_LOG:-}"
  fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    warn "没有日志，无法提取第一条错误。"
    return 0
  fi
  text=$(SRC="$src" php <<'PHP'
<?php
$src = getenv('SRC');
$raw = file_get_contents($src);
if ($raw === false) {
    exit(0);
}
$raw = str_replace(['&#039;', '&#39;'], "'", $raw);
$marker = '[Exception]';
$pos = strrpos($raw, $marker);
if ($pos === false) {
    $lines = preg_split("/\R/", $raw);
    $lines = array_values(array_filter($lines, static fn($line) => trim($line) !== ''));
    $slice = array_slice($lines, -15);
    echo "日志中没有 [Exception]，以下是末尾输出：\n";
    echo implode("\n", $slice);
    exit(0);
}
$after = ltrim(substr($raw, $pos + strlen($marker)), "\r\n");
$lines = preg_split("/\R/", $after);
echo implode("\n", array_slice($lines, 0, 15));
PHP
)
  FIRST_ERROR_BLOCK="$text"
  FIRST_ERROR_TEXT=$(printf '%s\n' "$text" | awk 'NF { print; exit }')
  printf '\n第一条错误原文：\n%s\n' "$text" >&2
  if [[ -n "${INSTALL_LOG:-}" && -f "$INSTALL_LOG" && "$src" != "$INSTALL_LOG" ]]; then
    {
      printf '\n===== print_first_error =====\n'
      printf '%s\n' "$text"
    } >>"$INSTALL_LOG"
  fi
}

ensure_sync_htaccess() {
  local dest="$APP_ROOT/config/sync/.htaccess"
  if [[ ! -d "$APP_ROOT/config/sync" ]]; then
    return 0
  fi
  cat >"$dest" <<'EOF'
# Deny all requests from Apache 2.4+.
<IfModule mod_authz_core.c>
  Require all denied
</IfModule>

# Deny all requests from Apache 2.0-2.2.
<IfModule !mod_authz_core.c>
  Deny from all
</IfModule>

# Turn off all options we don't need.
Options -Indexes -ExecCGI -Includes -MultiViews

# Set the catch-all handler to prevent scripts from being executed.
SetHandler Drupal_Security_Do_Not_Remove_See_SA_2006_006
<Files *>
  # Override the handler again if we're run later in the evaluation list.
  SetHandler Drupal_Security_Do_Not_Remove_See_SA_2013_003
</Files>

# If we know how to do it safely, disable the PHP engine entirely.
<IfModule mod_php.c>
  php_flag engine off
</IfModule>
EOF
  chmod 644 "$dest" || true
  log "已在工作副本 config/sync 写入拒绝访问的 .htaccess。该文件只存在于本次 clone，不会写回仓库。"
}

self_heal_config_sync() {
  local sync="$APP_ROOT/config/sync"
  local report del_file warn_file uuid_file name real count
  [[ -d "$sync" ]] || die "缺少 config/sync，无法自愈。"
  log "配置自愈：只检查 ${sync} 顶层 .yml。只读顶层 id 与 uuid，忽略 name、vid、type。不处理子目录，不重命名。"
  report=$(mktemp /tmp/xedc-self-heal.XXXXXX.txt)
  del_file=$(mktemp /tmp/xedc-self-heal-del.XXXXXX.txt)
  warn_file=$(mktemp /tmp/xedc-self-heal-warn.XXXXXX.txt)
  uuid_file=$(mktemp /tmp/xedc-self-heal-uuid.XXXXXX.txt)
  : >"$del_file"
  : >"$warn_file"
  : >"$uuid_file"
  if ! SYNC="$sync" php >"$report" <<'PHP'
<?php
declare(strict_types=1);

$sync = getenv('SYNC') ?: '';
if ($sync === '' || !is_dir($sync)) {
    fwrite(STDERR, "缺少 config/sync。\n");
    exit(1);
}
$root = realpath($sync);
if ($root === false) {
    fwrite(STDERR, "无法解析 config/sync。\n");
    exit(1);
}

function top_scalar(string $path, string $key): ?string {
    $handle = fopen($path, 'rb');
    if ($handle === false) {
        return null;
    }
    $prefix = $key . ':';
    while (($line = fgets($handle)) !== false) {
        if ($line === '' || $line[0] === ' ' || $line[0] === "\t" || $line[0] === '#') {
            continue;
        }
        if (!str_starts_with($line, $prefix)) {
            continue;
        }
        $value = trim(substr($line, strlen($prefix)));
        if ($value === '' || $value === '|' || $value === '>' || $value === '|-' || $value === '>-' || $value === '~' || strcasecmp($value, 'null') === 0) {
            fclose($handle);
            return null;
        }
        $quote = $value[0];
        if (strlen($value) >= 2 && ($quote === "'" || $quote === '"') && str_ends_with($value, $quote)) {
            $value = substr($value, 1, -1);
        }
        fclose($handle);
        return $value === '' ? null : $value;
    }
    fclose($handle);
    return null;
}

$files = [];
foreach (scandir($sync) ?: [] as $name) {
    if (!is_string($name) || !str_ends_with($name, '.yml')) {
        continue;
    }
    $path = $sync . '/' . $name;
    if (!is_file($path)) {
        continue;
    }
    $real = realpath($path);
    if ($real === false || !str_starts_with($real, $root . DIRECTORY_SEPARATOR)) {
        continue;
    }
    $files[] = [
        'name' => $name,
        'id' => top_scalar($path, 'id'),
        'uuid' => top_scalar($path, 'uuid'),
    ];
}

echo 'COUNT' . "\t" . count($files) . "\n";
$delete = [];
$warn = [];
foreach ($files as $file) {
    $id = $file['id'];
    if (!is_string($id) || $id === '') {
        continue;
    }
    $stem = substr($file['name'], 0, -4);
    if (str_ends_with($stem, '.' . $id)) {
        continue;
    }
    $matched = false;
    foreach ($files as $other) {
        if ($other['name'] === $file['name'] || $other['id'] !== $id) {
            continue;
        }
        $otherStem = substr($other['name'], 0, -4);
        if (!str_ends_with($otherStem, '.' . $id)) {
            continue;
        }
        if (str_replace('_', '.', $file['name']) === str_replace('_', '.', $other['name'])) {
            $matched = true;
            break;
        }
    }
    if ($matched) {
        $delete[] = $file['name'];
    } else {
        $warn[] = $file['name'];
    }
}
$deleteSet = array_fill_keys($delete, true);
foreach ($delete as $name) {
    echo 'DELETE' . "\t" . $name . "\n";
}
foreach ($warn as $name) {
    echo 'WARN' . "\t" . $name . "\n";
}
$byUuid = [];
foreach ($files as $file) {
    if (!is_string($file['uuid']) || $file['uuid'] === '') {
        continue;
    }
    $byUuid[$file['uuid']][] = $file['name'];
}
foreach ($byUuid as $uuid => $names) {
    if (count($names) < 2) {
        continue;
    }
    echo 'UUID' . "\t" . $uuid . "\t" . implode(',', $names) . "\n";
    $remain = array_values(array_filter($names, static fn(string $name): bool => !isset($deleteSet[$name])));
    if (count($remain) >= 2) {
        foreach ($remain as $name) {
            echo 'WARNUUID' . "\t" . $name . "\t" . $uuid . "\n";
        }
    }
}
PHP
  then
    warn "配置自愈扫描失败，没有删除任何文件。"
    SELF_HEAL_UNHANDLED="配置自愈扫描失败，未能读取顶层 id。"
    SELF_HEAL_RECORD=$'扫描失败，没有删除任何文件。\n'"${SELF_HEAL_UNHANDLED}"
    rm -f "$report" "$del_file" "$warn_file" "$uuid_file"
    return 0
  fi

  count=$(awk -F '\t' '$1=="COUNT" { print $2; exit }' "$report")
  count=${count:-0}
  log "已检查顶层 YAML ${count} 个。"
  awk -F '\t' '$1=="DELETE" { print $2 }' "$report" >"$del_file"
  awk -F '\t' '$1=="WARN" || $1=="WARNUUID" { print $2 }' "$report" | awk 'NF && !seen[$0]++' >"$warn_file"
  awk -F '\t' '$1=="UUID" { print $2 "\t" $3 }' "$report" >"$uuid_file"

  log "干运行结束。先列出将要删除的文件和只告警的文件，然后再删除。"
  printf '将要删除的文件：\n'
  if [[ ! -s "$del_file" ]]; then
    printf '  （无）\n'
  else
    sed 's/^/  - /' "$del_file"
  fi
  printf '只告警的文件：\n'
  if [[ ! -s "$warn_file" ]]; then
    printf '  （无）\n'
  else
    sed 's/^/  - /' "$warn_file"
  fi
  if [[ -s "$uuid_file" ]]; then
    log "同 uuid 只记录告警，不因此删除文件。"
    while IFS=$'\t' read -r uuid names; do
      [[ -z "$uuid" ]] && continue
      log "同 uuid ${uuid}：${names}"
    done <"$uuid_file"
  fi

  if [[ -s "$del_file" ]]; then
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if [[ ! "$name" =~ ^[A-Za-z0-9_.-]+\.yml$ ]]; then
        warn "拒绝删除异常文件名：${name}"
        printf '%s\n' "$name" >>"$warn_file"
        continue
      fi
      if [[ ! -f "$sync/$name" ]]; then
        warn "将要删除的文件已不存在：${name}"
        continue
      fi
      real=$(realpath -e "$sync/$name")
      case "$real" in
        "$sync"/*) ;;
        *)
          warn "拒绝删除同步目录之外的路径：${real}"
          continue
          ;;
      esac
      rm -f -- "$real"
      log "已删除工作副本中的 ${name}。"
    done <"$del_file"
  else
    log "没有需要删除的文件。"
  fi

  SELF_HEAL_RECORD=$(
    printf '检查顶层 YAML：%s\n' "$count"
    printf '将要删除：\n'
    if [[ -s "$del_file" ]]; then
      sed 's/^/- /' "$del_file"
    else
      printf -- '- （无）\n'
    fi
    printf '已删除：\n'
    if [[ -s "$del_file" ]]; then
      sed 's/^/- /' "$del_file"
    else
      printf -- '- （无）\n'
    fi
    printf '只告警：\n'
    if [[ -s "$warn_file" ]]; then
      sed 's/^/- /' "$warn_file"
    else
      printf -- '- （无）\n'
    fi
    printf '同 uuid（只告警，不因此删除）：\n'
    if [[ -s "$uuid_file" ]]; then
      while IFS=$'\t' read -r uuid names; do
        [[ -z "$uuid" ]] && continue
        printf -- '- %s：%s\n' "$uuid" "$names"
      done <"$uuid_file"
    else
      printf -- '- （无）\n'
    fi
  )
  if [[ -s "$warn_file" ]]; then
    SELF_HEAL_UNHANDLED=$(sed 's/^/无法自动处理：/' "$warn_file")
    warn "自愈后仍有只告警、未删除的文件。这些会计入预检失败。"
  else
    SELF_HEAL_UNHANDLED=""
  fi
  log "配置自愈结束。"
  if [[ "${INSTALL_LOG_READY:-0}" -eq 1 && -n "${SELF_HEAL_RECORD:-}" && -f "${INSTALL_LOG:-}" ]]; then
    {
      printf '\n===== 自愈记录 =====\n'
      printf '%s\n' "$SELF_HEAL_RECORD"
    } >>"$INSTALL_LOG"
  fi
  rm -f "$report" "$del_file" "$warn_file" "$uuid_file"
}

config_preflight() {
  local errfile
  errfile=$(mktemp /tmp/xedc-preflight.XXXXXX.txt)
  log "安装前预检 config/sync：必需文件、内容类型与词汇引用、模块和主题的 .info.yml。"
  if APP_ROOT="$APP_ROOT" php >"$errfile" 2>&1 <<'PHP'
<?php
declare(strict_types=1);

$appRoot = getenv('APP_ROOT') ?: '';
$sync = $appRoot . '/config/sync';
$errors = [];
if ($appRoot === '' || !is_dir($sync)) {
    fwrite(STDERR, "错误: 缺少 config/sync。\n");
    exit(1);
}
require $appRoot . '/vendor/autoload.php';

use Symfony\Component\Yaml\Exception\ParseException;
use Symfony\Component\Yaml\Yaml;

foreach (['core.extension.yml', 'system.site.yml'] as $required) {
    if (!is_file($sync . '/' . $required)) {
        $errors[] = "缺少 config/sync/{$required}";
    }
}

$patterns = [
    '/^field\.field\.node\.([^.]+)\..+\.yml$/' => 'node.type.%s.yml',
    '/^core\.entity_[a-z0-9_]+_display\.node\.([^.]+)\..+\.yml$/' => 'node.type.%s.yml',
    '/^field\.field\.taxonomy_term\.([^.]+)\..+\.yml$/' => 'taxonomy.vocabulary.%s.yml',
    '/^core\.entity_[a-z0-9_]+_display\.taxonomy_term\.([^.]+)\..+\.yml$/' => 'taxonomy.vocabulary.%s.yml',
];
$missingBundles = [];
foreach (scandir($sync) ?: [] as $name) {
    if (!is_string($name) || !str_ends_with($name, '.yml')) {
        continue;
    }
    foreach ($patterns as $regex => $template) {
        if (!preg_match($regex, $name, $matches)) {
            continue;
        }
        $needed = sprintf($template, $matches[1]);
        if (!is_file($sync . '/' . $needed)) {
            $missingBundles[$needed][] = $name;
        }
        break;
    }
}
foreach ($missingBundles as $needed => $sources) {
    $errors[] = "缺少 {$needed}，被这些配置引用：" . implode('、', $sources);
}

$extensionFile = $sync . '/core.extension.yml';
if (is_file($extensionFile)) {
    try {
        $extension = Yaml::parseFile($extensionFile);
    } catch (ParseException $exception) {
        $extension = null;
        $errors[] = '无法解析 core.extension.yml：' . $exception->getMessage();
    }
    if (is_array($extension)) {
        $wanted = [];
        foreach (['module', 'theme'] as $section) {
            if (!isset($extension[$section]) || !is_array($extension[$section])) {
                $errors[] = "core.extension.yml 缺少 {$section} 列表";
                continue;
            }
            foreach ($extension[$section] as $key => $value) {
                $name = '';
                if (is_string($key) && !preg_match('/^\d+$/', $key)) {
                    $name = $key;
                } elseif (is_string($value)) {
                    $name = $value;
                }
                $name = preg_replace('/:\s*\d+\s*$/', '', $name) ?? $name;
                $name = trim($name);
                if ($name === '' || !preg_match('/^[A-Za-z0-9_]+$/', $name)) {
                    $errors[] = "core.extension.yml 的 {$section} 含无法识别的名称";
                    continue;
                }
                $wanted[$section][$name] = true;
            }
        }
        $available = [];
        foreach ([$appRoot . '/web', $appRoot . '/vendor'] as $root) {
            if (!is_dir($root)) {
                continue;
            }
            $directory = new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS);
            $filter = new RecursiveCallbackFilterIterator(
                $directory,
                static function (SplFileInfo $current): bool {
                    if ($current->isDir()) {
                        $base = $current->getFilename();
                        $path = str_replace('\\', '/', $current->getPathname());
                        if ($base === 'node_modules' || $base === '.git' || str_contains($path, '/sites/default/files')) {
                            return false;
                        }
                    }
                    return true;
                }
            );
            foreach (new RecursiveIteratorIterator($filter) as $file) {
                if ($file->isFile() && str_ends_with($file->getFilename(), '.info.yml')) {
                    $available[$file->getFilename()] = true;
                }
            }
        }
        foreach ($wanted as $section => $names) {
            foreach (array_keys($names) as $name) {
                if (!isset($available[$name . '.info.yml'])) {
                    $errors[] = "core.extension.yml {$section}「{$name}」在 web/ 与 vendor/ 下都没有 {$name}.info.yml";
                }
            }
        }
    }
}

if ($errors !== []) {
    fwrite(STDERR, '配置预检失败，共 ' . count($errors) . " 个问题：\n");
    foreach ($errors as $error) {
        fwrite(STDERR, "错误: {$error}\n");
    }
    exit(1);
}
echo "配置预检通过。\n";
PHP
  then
    PREFLIGHT_STATUS="通过"
    PREFLIGHT_FAILED=0
    PREFLIGHT_ERRORS=""
    cat "$errfile"
    rm -f "$errfile"
    return 0
  fi
  PREFLIGHT_STATUS="预检失败"
  PREFLIGHT_FAILED=1
  PREFLIGHT_ERRORS=$(cat "$errfile" || true)
  if [[ -n "${SELF_HEAL_UNHANDLED:-}" ]]; then
    PREFLIGHT_ERRORS="${SELF_HEAL_UNHANDLED}
${PREFLIGHT_ERRORS}"
  fi
  printf '%s\n' "$PREFLIGHT_ERRORS" >&2
  rm -f "$errfile"
  warn "配置预检未通过。上面已列出具体错误。已阻止 site:install，脚本会继续写凭据文件。"
  return 0
}
finish_config_preflight() {
  if [[ "$PREFLIGHT_FAILED" -eq 0 && -n "${SELF_HEAL_UNHANDLED:-}" ]]; then
    PREFLIGHT_STATUS="预检失败"
    PREFLIGHT_FAILED=1
    PREFLIGHT_ERRORS="$SELF_HEAL_UNHANDLED"
    printf '%s\n' "$PREFLIGHT_ERRORS" >&2
    warn "自愈后仍有无法自动处理的配置问题。已阻止 site:install，脚本会继续写凭据文件。"
  fi
}

extract_install_stack() {
  local src label stack
  label="$1"
  src="${LAST_DRUSH_LOG:-}"
  if [[ -z "$src" || ! -f "$src" ]]; then
    src="${INSTALL_LOG:-}"
  fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    warn "没有安装日志，无法提取模块堆栈。"
    return 0
  fi
  stack=$(awk '
    /Missing bundle entity|\[Exception\]/ { n = 0; delete kept }
    /modules\// || /profiles\// {
      n++
      kept[n] = $0
    }
    END {
      show = n + 0
      if (show > 15) {
        show = 15
      }
      for (i = 1; i <= show; i++) {
        print kept[i]
      }
    }
  ' "$src" || true)
  {
    echo ""
    echo "===== site:install stack ${label} ====="
    if [[ -n "$stack" ]]; then
      printf '%s\n' "$stack"
    else
      echo "堆栈中没有 modules/、core/modules 或 profiles/ 路径。"
    fi
  } >>"$INSTALL_LOG"
  if [[ -n "$stack" ]]; then
    printf '\n安装失败堆栈（%s，含模块路径的前 15 行）：\n%s\n' "$label" "$stack" >&2
  else
    warn "site:install 失败（${label}），堆栈中没有 modules/、core/modules 或 profiles/ 路径。"
  fi
  return 0
}

run_site_install_existing() {
  local db_url previous
  local -a args
  db_url=$(drupal_db_url)
  args=(
    -vvv
    site:install
    --existing-config
    --config-dir="$APP_ROOT/config/sync"
    -y
    "--site-name=${DRUPAL_SITE_NAME}"
    "--site-mail=${DRUPAL_SITE_MAIL}"
    "--account-name=${DRUPAL_ADMIN_USER}"
    "--account-pass=${DRUPAL_ADMIN_PASS}"
    "--account-mail=${DRUPAL_SITE_MAIL}"
    "--db-url=${db_url}"
  )
  prepare_install_log
  log "执行 drush -vvv site:install --existing-config --config-dir=${APP_ROOT}/config/sync（--locale=zh-hans）。输出写入 ${INSTALL_LOG}。"
  if run_drush "${args[@]}" --locale=zh-hans; then
    log "site:install --existing-config 已成功。"
  else
    warn "site:install --existing-config（zh-hans）返回错误。这不代表整体失败，稍后仍会执行 drush cim。"
    extract_install_stack "zh-hans" || true
    if site_installed; then
      warn "安装器已留下数据库表。不清空数据库，也不因已有表而跳过后续 cim。"
    else
      warn "数据库里还没有 Drupal 站点。清空后去掉 --locale 再试一次 site:install。"
      {
        echo ""
        echo "===== retry site:install --existing-config without --locale ====="
      } >>"$INSTALL_LOG"
      previous="$REINSTALL"
      REINSTALL=1
      apply_database
      REINSTALL="$previous"
      write_settings
      fix_permissions writable-settings
      if run_drush "${args[@]}"; then
        log "不带 --locale 的 site:install --existing-config 已成功。"
      else
        warn "不带 --locale 的 site:install 仍返回错误。继续执行 drush cim。"
        extract_install_stack "without-locale" || true
      fi
    fi
  fi
  DID_INSTALL=1
  return 0
}

summarize_import_failure() {
  local reason="$1"
  local src
  IMPORT_FAILED=1
  warn "配置导入未成功。${reason}"
  src="${CIM_LOG:-$INSTALL_LOG}"
  if [[ -n "$src" && -f "$src" ]]; then
    warn "错误摘要（${src} 末尾 40 行）："
    tail -n 40 "$src" >&2 || true
  fi
  cat >&2 <<'EOF'

可能原因：
- config/sync 引用的模块、主题或 bundle 在当前代码里不存在
- system.site 的 UUID 与 config/sync/system.site.yml 不一致
- 配置实体 ID 重复，且不属于可自动删除的配置实体

已生成的数据库口令不会回滚。可在修正配置后重新执行本脚本。
EOF
}

point_config_at_sync_or_fail() {
  local current
  capture_stray_config_dir
  ensure_config_sync_directory
  if ! current=$(settings_config_sync_value "$APP_ROOT/web/sites/default/settings.php"); then
    warn "无法读取 config_sync_directory，中止本次配置导入。"
    return 1
  fi
  if [[ "$current" != "../config/sync" && "$current" != "$APP_ROOT/config/sync" ]]; then
    warn "config_sync_directory 仍是 ${current}，中止本次配置导入。"
    return 1
  fi
  return 0
}

parse_entity_already_exists() {
  local src="$1"
  local parsed rc
  PARSED_ENTITY_TYPE=""
  PARSED_ENTITY_ID=""
  if [[ ! -f "$src" ]]; then
    warn "没有本次 drush 日志，无法判断配置冲突。"
    return 1
  fi
  set +e
  parsed=$(SRC="$src" php <<'PHP'
<?php
$src = getenv('SRC');
$raw = file_get_contents($src);
if ($raw === false) {
    exit(1);
}
$raw = str_replace(['&#039;', '&#39;'], "'", $raw);
if (!preg_match("/entity with ID '([^']+)' already exists/", $raw, $idMatch)) {
    exit(1);
}
$entityId = $idMatch[1];
$pattern = "/(?<![A-Za-z0-9_])([A-Za-z0-9_]+)\\.([A-Za-z0-9_]+)\\." . preg_quote($entityId, '/') . "(?![A-Za-z0-9_.])/";
if (!preg_match($pattern, $raw, $nameMatch)) {
    exit(2);
}
echo $nameMatch[2], "\n", $entityId, "\n";
PHP
  )
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]]; then
    warn "该错误不含 entity with ID already exists，不自动处理。"
    return 1
  fi
  if [[ "$rc" -ne 0 || -z "$parsed" ]]; then
    warn "无法从配置名前缀推断实体类型，不自动删除。"
    return 1
  fi
  PARSED_ENTITY_TYPE=$(printf '%s\n' "$parsed" | sed -n '1p')
  PARSED_ENTITY_ID=$(printf '%s\n' "$parsed" | sed -n '2p')
  if [[ ! "$PARSED_ENTITY_TYPE" =~ ^[A-Za-z0-9_]+$ || ! "$PARSED_ENTITY_ID" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    warn "解析出的实体类型或 ID 无法安全删除，不自动处理。"
    return 1
  fi
  case "$PARSED_ENTITY_TYPE" in
    node|user|media)
      warn "拒绝删除内容实体 ${PARSED_ENTITY_TYPE}/${PARSED_ENTITY_ID}。只允许删除配置实体。"
      return 1
      ;;
  esac
  return 0
}

mark_import_failure() {
  local reason="$1"
  IMPORT_FAILED=1
  CIM_JUDGED_OK=0
  OVERALL_STATUS="失败"
  FAIL_REASON="$reason"
  if [[ "$reason" == 失败：* ]]; then
    CONFIG_IMPORT_STATUS="$reason"
  else
    CONFIG_IMPORT_STATUS="失败"
  fi
  warn "$reason"
}

sync_top_yml_count() {
  local count
  count=$(find "$APP_ROOT/config/sync" -maxdepth 1 -type f -name '*.yml' 2>/dev/null | wc -l | tr -d '[:space:]')
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    count=0
  fi
  printf '%s\n' "$count"
}

node_type_yml_count() {
  local count
  count=$(find "$APP_ROOT/config/sync" -maxdepth 1 -type f -name 'node.type.*.yml' 2>/dev/null | wc -l | tr -d '[:space:]')
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    count=0
  fi
  printf '%s\n' "$count"
}

database_node_type_count() {
  local table count
  if [[ -z "${SQL_BIN:-}" || -z "${DB_NAME:-}" ]]; then
    printf '0\n'
    return 0
  fi
  table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='node_type'")
  if [[ "$table" -eq 0 ]]; then
    printf '0\n'
    return 0
  fi
  count=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.node_type")
  printf '%s\n' "$count"
}

filter_config_names() {
  awk '{
    gsub(/^[ \t]+|[ \t]+$/, "")
    if ($0 ~ /^[A-Za-z0-9][A-Za-z0-9_.]*$/ && index($0, ".")) print
  }'
}

drush_text() {
  local raw
  set +e
  raw=$(run_drush "$@")
  set -e
  printf '%s\n' "$raw"
}

drush_config_names() {
  local raw rc
  set +e
  raw=$(run_drush "$@")
  rc=$?
  set -e
  printf '%s\n' "$raw" | filter_config_names
  return "$rc"
}

semaphore_names() {
  local raw
  raw=$(drush_text sqlq "SELECT name FROM semaphore WHERE name LIKE 'config_importer%'")
  printf '%s\n' "$raw" | grep -E '^config_importer' || true
}

release_config_lock() {
  local names
  names=$(semaphore_names)
  if [[ -z "$names" ]]; then
    log "没有 config_importer 锁需要释放。"
    return 0
  fi
  if ! database_has_no_real_content; then
    mark_import_failure "配置导入锁未释放，且库内已有真实站点内容，拒绝删除锁"
    return 1
  fi
  log "库内没有真实站点内容，删除配置锁：${names}"
  if ! run_drush sqlq "DELETE FROM semaphore WHERE name LIKE 'config_importer%'"; then
    mark_import_failure "删除 config_importer 锁失败"
    return 1
  fi
  return 0
}

wait_config_lock_and_verify_sync() {
  local start now elapsed names files storage raw settings_out count_gap
  log "重建缓存后检查 config_importer 锁。"
  if ! run_drush cr; then
    warn "drush cr 未成功，仍继续检查配置锁。"
  fi
  start=$(date +%s)
  while true; do
    names=$(semaphore_names)
    if [[ -z "$names" ]]; then
      log "配置导入锁已释放。"
      break
    fi
    now=$(date +%s)
    elapsed=$((now - start))
    if [[ "$elapsed" -ge 60 ]]; then
      log "等待配置锁已达 ${elapsed} 秒，仍存在：${names}"
      if ! database_has_no_real_content; then
        mark_import_failure "配置导入锁未释放，且库内已有真实站点内容，拒绝删除锁"
        return 1
      fi
      log "库内没有真实站点内容，删除 config_importer 锁。"
      if ! run_drush sqlq "DELETE FROM semaphore WHERE name LIKE 'config_importer%'"; then
        mark_import_failure "等待 60 秒后删除 config_importer 锁失败"
        return 1
      fi
      break
    fi
    log "配置锁仍在（${elapsed}s/60s）：${names}"
    sleep 3
  done

  files=$(sync_top_yml_count)
  set +e
  raw=$(run_drush php:eval 'echo count(\Drupal::service("config.storage.sync")->listAll());')
  set -e
  storage=$(printf '%s\n' "$raw" | awk '/^[0-9]+$/ { n = $0 } END { print n + 0 }')
  SYNC_LIST_COUNT="$storage"
  log "工作副本 config/sync 顶层 YAML ${files} 个，config.storage.sync 列出 ${storage} 个。当前目录：$(pwd)"
  count_gap=$((files > storage ? files - storage : storage - files))
  if [[ "$storage" -eq 0 || "$count_gap" -gt 2 ]]; then
    set +e
    settings_out=$(run_drush php:eval 'echo \Drupal\Core\Site\Settings::get("config_sync_directory"), PHP_EOL, getcwd();')
    set -e
    mark_import_failure "失败：同步目录不可读"
    {
      echo ""
      echo "===== 同步目录不可读 ====="
      echo "shell pwd: $(pwd)"
      echo "顶层 YAML: ${files}"
      echo "listAll: ${storage}"
      echo "Settings::get(config_sync_directory) 与 PHP getcwd："
      printf '%s\n' "$settings_out"
    } >>"$INSTALL_LOG"
    printf '\n失败：同步目录不可读\n当前目录：%s\n顶层 YAML：%s\nlistAll：%s\n%s\n' "$(pwd)" "$files" "$storage" "$settings_out" >&2
    return 1
  fi
  return 0
}

# 返回 0 表示不得执行 cim。Only in sync dir 为 0 且文件存在时，若同步存储可读、
# 计划不会删除 core.extension / system.site / node.type.*，且库里已有 node 类型，
# 则视为已经导入过，允许继续 cim，避免重复运行被误判。
# core.entity_view_mode.*.token 在调用前已从 Only in DB 列表去掉。
import_plan_is_abnormal() {
  local only_db="$1"
  local only_sync_count="$2"
  local yml_count="$3"
  local storage_count="$4"
  local db_node_types="$5"
  local dangerous storage_gap expected_types
  dangerous=$(printf '%s\n' "$only_db" | grep -E '^(core\.extension|system\.site|node\.type\..+)$' || true)
  if [[ -n "$dangerous" ]]; then
    log "导入计划将删除核心配置：$(printf '%s\n' "$dangerous" | paste -sd, -)"
    return 0
  fi
  if [[ "$only_sync_count" -eq 0 && "$yml_count" -gt 0 ]]; then
    storage_gap=$((yml_count > storage_count ? yml_count - storage_count : storage_count - yml_count))
    if [[ "$storage_count" -eq 0 || "$storage_gap" -gt 2 ]]; then
      log "Only in sync dir 为 0，同步存储列出 ${storage_count} 项，顶层 YAML 有 ${yml_count} 个。"
      return 0
    fi
    expected_types=$(node_type_yml_count)
    if [[ "$db_node_types" -eq 0 && "$expected_types" -gt 0 ]]; then
      log "Only in sync dir 为 0，config/sync 有 ${expected_types} 个 node.type，数据库 node 类型为 0。"
      return 0
    fi
    log "Only in sync dir 为 0，同步存储可读，且计划不会删除 core.extension、system.site 或 node.type.*。"
  fi
  return 1
}

verify_import_plan() {
  local attempt only_db only_sync only_sync_count yml_count db_nodes detail
  local db_rc sync_rc
  yml_count=$(sync_top_yml_count)
  for attempt in 1 2 3; do
    if ! wait_config_lock_and_verify_sync; then
      return 1
    fi
    set +e
    only_db=$(drush_config_names config:status --state='Only in DB' --format=list)
    db_rc=$?
    only_sync=$(drush_config_names config:status --state='Only in sync dir' --format=list)
    sync_rc=$?
    set -e
    only_db=$(printf '%s\n' "$only_db" | grep -Ev '^core\.entity_view_mode\..+\.token$' || true)
    only_sync_count=$(printf '%s\n' "$only_sync" | awk 'NF { c++ } END { print c + 0 }')
    db_nodes=$(database_node_type_count)
    log "导入计划第 ${attempt}/3 次：Only in sync dir ${only_sync_count} 项，数据库 node 类型 ${db_nodes} 个。"
    detail=$(
      printf 'Only in DB（前 20 项，已忽略 core.entity_view_mode.*.token）：\n'
      if [[ -n "$only_db" ]]; then
        printf '%s\n' "$only_db" | awk 'NF { c++; if (c <= 20) print }'
      else
        printf '（无）\n'
      fi
      printf 'Only in sync dir（前 20 项）：\n'
      if [[ -n "$only_sync" ]]; then
        printf '%s\n' "$only_sync" | awk 'NF { c++; if (c <= 20) print }'
      else
        printf '（无）\n'
      fi
    )
    PLAN_DETAIL="$detail"
    if [[ "$db_rc" -ne 0 || "$sync_rc" -ne 0 ]]; then
      warn "config:status 退出码非 0，仍按解析出的名单判断导入计划（第 ${attempt}/3 次）。"
    fi
    if ! import_plan_is_abnormal "$only_db" "$only_sync_count" "$yml_count" "$SYNC_LIST_COUNT" "$db_nodes"; then
      log "导入计划可以执行 cim。"
      return 0
    fi
    warn "导入计划异常（第 ${attempt}/3 次）。"
    if [[ "$attempt" -eq 3 ]]; then
      break
    fi
    if ! release_config_lock; then
      return 1
    fi
    log "等待 10 秒并重建缓存后重新验证导入计划。"
    sleep 10
    if ! run_drush cr; then
      warn "重新验证前的 drush cr 未成功。"
    fi
  done
  mark_import_failure "失败：导入计划异常"
  {
    echo ""
    echo "===== 导入计划异常 ====="
    printf '%s\n' "$PLAN_DETAIL"
  } >>"$INSTALL_LOG"
  printf '\n失败：导入计划异常\n%s\n' "$PLAN_DETAIL" >&2
  return 1
}

cim_log_has() {
  local needle="$1"
  [[ -n "${LAST_DRUSH_LOG:-}" && -f "$LAST_DRUSH_LOG" ]] || return 1
  grep -q -F -- "$needle" "$LAST_DRUSH_LOG"
}

run_cim_with_lock_retries() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if ! wait_config_lock_and_verify_sync; then
      return 1
    fi
    log "执行 drush cim -y（第 ${attempt}/5 次）。成功必须看到导入成功原文，且不能出现配置锁警告。"
    if ! run_drush cim -y; then
      log "drush cim 退出码非 0，改按输出判定。"
    fi
    if cim_log_has "Another request may be synchronizing"; then
      warn "第 ${attempt}/5 次 cim 出现配置锁警告，视为未执行。"
      continue
    fi
    if cim_log_has "The configuration was imported successfully"; then
      CIM_JUDGED_OK=1
      log "drush cim 判定成功。"
      return 0
    fi
    if cim_log_has "There are no changes to import"; then
      CIM_JUDGED_OK=1
      log "drush cim 判定成功（没有需要导入的变更）。"
      return 0
    fi
    if cim_log_has "entity with ID"; then
      return 2
    fi
    warn "第 ${attempt}/5 次 cim 的输出不含成功原文。"
  done
  mark_import_failure "cim 在 5 次尝试后仍未出现成功原文，或仍被配置锁挡住"
  return 1
}

resolve_config_conflicts() {
  local round rc
  for round in 1 2 3 4 5 6 7 8; do
    if ! parse_entity_already_exists "$LAST_DRUSH_LOG"; then
      return 1
    fi
    log "配置冲突第 ${round}/8 轮：删除配置实体 ${PARSED_ENTITY_TYPE} ${PARSED_ENTITY_ID}，然后重试 drush cim -y。"
    {
      echo ""
      echo "===== resolve round ${round}: entity:delete ${PARSED_ENTITY_TYPE} ${PARSED_ENTITY_ID} ====="
    } >>"$INSTALL_LOG"
    if ! run_drush entity:delete "$PARSED_ENTITY_TYPE" "$PARSED_ENTITY_ID" -y; then
      warn "删除配置实体失败，停止自动处理。"
      return 1
    fi
    rc=0
    run_cim_with_lock_retries || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      log "第 ${round} 轮后 drush cim 判定成功。"
      return 0
    fi
    if [[ "$rc" -ne 2 ]]; then
      return 1
    fi
  done
  warn "配置冲突已处理 8 轮，drush cim 仍未成功。"
  return 1
}

collect_config_diffs() {
  local raw rc
  CONFIG_DIFF_NAMES=""
  set +e
  raw=$(run_drush config:status --format=list)
  rc=$?
  set -e
  CONFIG_DIFF_NAMES=$(printf '%s\n' "$raw" | awk '{
    gsub(/^[ \t]+|[ \t]+$/, "")
    if ($0 ~ /^[A-Za-z0-9][A-Za-z0-9_.]*$/ && index($0, ".")) print
  }')
  if [[ -z "$CONFIG_DIFF_NAMES" ]]; then
    CONFIG_DIFF_COUNT=0
  else
    CONFIG_DIFF_COUNT=$(printf '%s\n' "$CONFIG_DIFF_NAMES" | awk 'NF { c++ } END { print c + 0 }')
  fi
  if [[ "$rc" -ne 0 ]]; then
    warn "drush config:status --format=list 未能正常结束。"
    if [[ "$CONFIG_DIFF_COUNT" == "0" && -z "$CONFIG_DIFF_NAMES" ]]; then
      CONFIG_DIFF_COUNT="未知"
    fi
    return 1
  fi
  log "drush config:status 差异数量：${CONFIG_DIFF_COUNT}。"
  return 0
}

log_remaining_diffs() {
  local name sync_file cex_file shown=0
  {
    echo ""
    echo "===== remaining config:status ====="
    if [[ -n "$CONFIG_DIFF_NAMES" ]]; then
      printf '%s\n' "$CONFIG_DIFF_NAMES"
    else
      echo "(none)"
    fi
    echo "===== first 20 diffs, up to 5 lines each ====="
  } >>"$INSTALL_LOG"
  if [[ -z "$CONFIG_DIFF_NAMES" ]]; then
    return 0
  fi
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    shown=$((shown + 1))
    if [[ "$shown" -gt 20 ]]; then
      break
    fi
    sync_file="$APP_ROOT/config/sync/${name}.yml"
    cex_file="/tmp/xedc-cex/${name}.yml"
    {
      echo "--- ${name} ---"
      if [[ -f "$sync_file" && -f "$cex_file" ]]; then
        set +e
        set +o pipefail
        diff -u "$sync_file" "$cex_file" 2>/dev/null | head -n 5
        set -o pipefail
        set -e
      elif [[ ! -f "$sync_file" ]]; then
        echo "只存在于活动配置"
      else
        echo "只存在于工作副本 config/sync"
      fi
    } >>"$INSTALL_LOG"
  done <<< "$CONFIG_DIFF_NAMES"
}

log_partial_success_details() {
  local only_sync different distribution
  {
    echo ""
    echo "===== 差异分布 ====="
    if [[ -n "$CONFIG_DIFF_NAMES" ]]; then
      distribution=$(printf '%s\n' "$CONFIG_DIFF_NAMES" | awk '
        NF {
          n = split($0, parts, ".")
          if (n >= 2) {
            prefix = parts[1] "." parts[2]
          } else {
            prefix = $0
          }
          count[prefix]++
        }
        END {
          for (prefix in count) {
            printf "%d\t%s\n", count[prefix], prefix
          }
        }
      ' | sort -t "$(printf '\t')" -k1,1nr)
      printf '%s\n' "$distribution" | awk -F '\t' '{ printf "%s %s\n", $2, $1 }'
      printf '分布：'
      printf '%s\n' "$distribution" | awk -F '\t' 'NF { printf "%s%s %s", sep, $2, $1; sep="、" } END { print "" }'
    else
      echo "（无）"
    fi
  } >>"$INSTALL_LOG"
  set +e
  only_sync=$(drush_config_names config:status --state='Only in sync dir' --format=list)
  different=$(drush_config_names config:status --state='Different' --format=list)
  set -e
  {
    echo "===== Only in sync dir（全部） ====="
    if [[ -n "$only_sync" ]]; then
      printf '%s\n' "$only_sync"
    else
      echo "（无）"
    fi
    echo "===== Different（前 30） ====="
    if [[ -n "$different" ]]; then
      printf '%s\n' "$different" | awk 'NF { c++; if (c <= 30) print }'
    else
      echo "（无）"
    fi
  } >>"$INSTALL_LOG"
  log_remaining_diffs || true
}

multi_pass_config_import() {
  local round prev current stale rc
  stale=0
  if collect_config_diffs; then
    prev="$CONFIG_DIFF_COUNT"
  else
    prev="未知"
  fi
  log "首轮 cim 判定成功后的配置差异：${prev}"
  {
    echo ""
    echo "===== cim pass 0 diff ${prev} ====="
    printf '%s\n' "$CONFIG_DIFF_NAMES"
  } >>"$INSTALL_LOG"
  if [[ "$prev" == "0" ]]; then
    log "配置差异已是 0，不再继续多轮 cim。"
    return 0
  fi
  for round in 1 2 3 4 5 6; do
    log "多轮导入第 ${round}/6 轮。"
    rc=0
    run_cim_with_lock_retries || rc=$?
    if [[ "$rc" -eq 2 ]]; then
      if ! resolve_config_conflicts; then
        mark_import_failure "多轮导入第 ${round} 轮遇到配置冲突且未能消除"
        return 1
      fi
    elif [[ "$rc" -ne 0 ]]; then
      return 1
    fi
    if collect_config_diffs; then
      current="$CONFIG_DIFF_COUNT"
    else
      current="未知"
    fi
    log "第 ${round} 轮后配置差异：${current}"
    {
      echo ""
      echo "===== cim pass ${round} diff ${current} ====="
      printf '%s\n' "$CONFIG_DIFF_NAMES"
    } >>"$INSTALL_LOG"
    if [[ "$current" == "0" ]]; then
      log "配置差异已降到 0。"
      return 0
    fi
    if [[ "$current" =~ ^[0-9]+$ && "$prev" =~ ^[0-9]+$ && "$current" -lt "$prev" ]]; then
      stale=0
    else
      stale=$((stale + 1))
    fi
    prev="$current"
    if [[ "$stale" -ge 2 ]]; then
      log "配置差异连续两轮没有减少，停止多轮导入。"
      return 0
    fi
  done
  log "多轮导入已达 6 轮。"
  return 0
}

reconcile_display_diffs() {
  local copied py_rc copy_count keep_count
  if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    log "安装 python3-yaml，用于比较配置差异。"
    if ! apt-get install -y python3-yaml; then
      warn "无法安装 python3-yaml，不回写任何差异文件。"
      return 1
    fi
  fi
  rm -rf /tmp/xedc-cex
  install -d -o "$WEB_USER" -g "$WEB_USER" -m 700 /tmp/xedc-cex
  log "导出活动配置到 /tmp/xedc-cex。只在内容一致，或 display 仅有发布时间字段不同时，回写工作副本。不执行 git commit。"
  if ! run_drush cex -y --destination=/tmp/xedc-cex; then
    warn "drush cex 未成功，不回写任何差异文件。"
    return 1
  fi
  set +e
  copied=$(SYNC="$APP_ROOT/config/sync" CEX=/tmp/xedc-cex python3 - "$CONFIG_DIFF_NAMES" <<'PY'
import copy
import os
import shutil
import sys
from pathlib import Path

import yaml

sync = Path(os.environ["SYNC"])
cex = Path(os.environ["CEX"])
names = [line.strip() for line in sys.argv[1].splitlines() if line.strip()]
forbidden = ("views.view.", "node.type.", "field.", "media.type.")
display = ("core.entity_form_display.", "core.entity_view_display.")

def load_yaml(path):
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)

def strip_scheduler(data):
    data = copy.deepcopy(data)
    if isinstance(data, dict):
        for section in ("hidden", "content"):
            block = data.get(section)
            if isinstance(block, dict):
                block.pop("publish_on", None)
                block.pop("unpublish_on", None)
    return data

def safe_name(name):
    return bool(name) and all(ch.isalnum() or ch in "._" for ch in name)

for name in names:
    if not safe_name(name):
        print(f"KEEP\t{name}\t文件名不安全")
        continue
    if name.startswith(forbidden):
        print(f"KEEP\t{name}\t禁止回写")
        continue
    src = cex / f"{name}.yml"
    dst = sync / f"{name}.yml"
    if not src.is_file() or not dst.is_file():
        print(f"KEEP\t{name}\t导出文件或工作副本缺少对应 YAML")
        continue
    try:
        exported = load_yaml(src)
        original = load_yaml(dst)
    except Exception:
        print(f"KEEP\t{name}\t无法解析 YAML")
        continue
    reason = ""
    if exported == original:
        reason = "内容相同（忽略键顺序）"
    elif name.startswith(display) and strip_scheduler(exported) == strip_scheduler(original):
        reason = "仅 hidden/content 下的 publish_on、unpublish_on 不同"
    if reason == "":
        print(f"KEEP\t{name}\t内容不同，保留工作副本")
        continue
    try:
        shutil.copyfile(src, dst)
    except OSError:
        print(f"KEEP\t{name}\t无法写回工作副本")
        continue
    print(f"COPY\t{name}\t{reason}")
PY
  )
  py_rc=$?
  set -e
  if [[ "$py_rc" -ne 0 ]]; then
    warn "比较配置 YAML 失败，不回写。"
    return 1
  fi
  {
    echo ""
    echo "===== config diff reconcile ====="
    if [[ -n "$copied" ]]; then
      printf '%s\n' "$copied"
    else
      echo "(none)"
    fi
  } >>"$INSTALL_LOG"
  copy_count=$(printf '%s\n' "$copied" | awk -F '\t' '$1=="COPY" { c++ } END { print c + 0 }')
  keep_count=$(printf '%s\n' "$copied" | awk -F '\t' '$1=="KEEP" { c++ } END { print c + 0 }')
  log "已回写工作副本 ${copy_count} 项，保留 ${keep_count} 项。明细在 ${INSTALL_LOG}。这些文件只存在于本次 clone，不会提交。"
  if [[ "$copy_count" -gt 0 ]]; then
    printf '%s\n' "$copied" | awk -F '\t' '$1=="COPY" { print "  - " $2 "（" $3 "）" }'
  fi
  return 0
}

finalize_config_status() {
  if [[ "$CIM_JUDGED_OK" -ne 1 || "$IMPORT_FAILED" -ne 0 ]]; then
    log "cim 未判定成功，不回写 display 差异。原因：${FAIL_REASON:-未执行}"
    return 0
  fi
  if ! collect_config_diffs; then
    warn "回写前未能统计 config:status。"
    return 0
  fi
  if [[ "$CONFIG_DIFF_COUNT" == "0" ]]; then
    log "多轮导入后 config:status 没有差异，不回写。"
    return 0
  fi
  log "多轮导入后仍有 ${CONFIG_DIFF_COUNT} 项差异，开始比较导出文件。"
  if ! reconcile_display_diffs; then
    warn "差异比较未完成，保留现有工作副本。"
  fi
  if ! collect_config_diffs; then
    warn "回写后未能再次统计 config:status。"
  else
    log "回写后 config:status 差异数量：${CONFIG_DIFF_COUNT}。"
  fi
  return 0
}

import_config_with_retries() {
  local uuid rc
  prepare_install_log
  if site_installed; then
    if ! point_config_at_sync_or_fail; then
      mark_import_failure "config_sync_directory 无法指回 ../config/sync"
      summarize_import_failure "未能把 config_sync_directory 指回 ../config/sync。"
      return 0
    fi
    if uuid=$(read_site_uuid); then
      log "导入前对齐 system.site uuid ${uuid}。"
      if ! run_drush config:set system.site uuid "$uuid" -y; then
        warn "未能写入系统 UUID，继续尝试导入。"
      fi
    else
      warn "未能从 system.site.yml 读取 UUID，继续尝试导入。"
    fi
  else
    warn "site:install 之后数据库里仍没有 Drupal 站点。仍会执行 drush cim，失败则按真实结果写失败。"
  fi
  if ! verify_import_plan; then
    if [[ "$CONFIG_IMPORT_STATUS" != 失败：* ]]; then
      summarize_import_failure "${FAIL_REASON:-导入前校验未通过，未执行 cim。}"
    else
      summarize_import_failure "$CONFIG_IMPORT_STATUS"
    fi
    return 0
  fi
  rc=0
  run_cim_with_lock_retries || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    if ! resolve_config_conflicts; then
      summarize_import_failure "drush cim 未成功。"
      if [[ "$IMPORT_FAILED" -eq 0 ]]; then
        mark_import_failure "drush cim 未成功"
      fi
      return 0
    fi
  elif [[ "$rc" -ne 0 ]]; then
    summarize_import_failure "${FAIL_REASON:-drush cim 未成功。}"
    return 0
  fi
  if ! multi_pass_config_import; then
    summarize_import_failure "${FAIL_REASON:-多轮 drush cim 未成功。}"
    return 0
  fi
  if ! run_drush updatedb -y; then
    warn "导入后的 drush updatedb 未成功。"
  fi
  capture_stray_config_dir
  return 0
}

log_skipped_followups() {
  local reason="${1:-${FAIL_REASON:-cim 未判定成功}}"
  warn "跳过主题安装、默认主题写入、翻译导入和 display 差异回写。原因：${reason}"
  if [[ -n "${INSTALL_LOG:-}" && -f "$INSTALL_LOG" ]]; then
    {
      echo ""
      echo "===== skip theme, translation, display writeback ====="
      printf '%s\n' "$reason"
    } >>"$INSTALL_LOG"
  fi
}

php_fpm_log_path() {
  local conf line path
  local -a confs
  confs=(/etc/php/8.5/fpm/php-fpm.conf /etc/php/8.5/fpm/pool.d/www.conf)
  for conf in "${confs[@]}"; do
    if [[ ! -f "$conf" ]]; then
      continue
    fi
    line=$(grep -E '^[[:space:]]*error_log[[:space:]]*=' "$conf" | tail -n 1 || true)
    path="${line#*=}"
    path="${path%%;*}"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    if [[ -n "$path" && -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  if [[ -f /var/log/php8.5-fpm.log ]]; then
    printf '%s\n' /var/log/php8.5-fpm.log
    return 0
  fi
  return 1
}

last_error_lines() {
  local file="$1"
  local lines=""
  if [[ -f "$file" && -r "$file" ]]; then
    lines=$(tail -n 400 "$file" | grep -E '\[error\]|\[crit\]|\[alert\]|\[emerg\]|PHP Fatal|PHP Parse|Uncaught|TypeError' | tail -n 3 || true)
  fi
  printf '%s\n' "$lines"
}

capture_http_error_excerpt() {
  local fpm nginx_lines fpm_lines
  nginx_lines=$(last_error_lines /var/log/nginx/error.log)
  fpm="未找到"
  fpm_lines=""
  if fpm=$(php_fpm_log_path); then
    fpm_lines=$(last_error_lines "$fpm")
  fi
  HTTP_ERROR_EXCERPT=$(
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
  )
  printf '\n首页 5xx，最近错误如下：\n%s\n' "$HTTP_ERROR_EXCERPT" >&2
  if [[ -n "${INSTALL_LOG:-}" && -f "$INSTALL_LOG" ]]; then
    {
      echo ""
      echo "===== homepage 5xx ====="
      printf '%s\n' "$HTTP_ERROR_EXCERPT"
    } >>"$INSTALL_LOG"
  fi
}

decide_overall_status() {
  local http_code="$1"
  local node_actual="$2"
  local node_expected="$3"
  local http_good=0 nodes_good=0 why=""
  if [[ "$http_code" == "200" || "$http_code" =~ ^3[0-9][0-9]$ ]]; then
    http_good=1
  fi
  if [[ "$node_actual" =~ ^[0-9]+$ && "$node_expected" =~ ^[0-9]+$ && "$node_actual" -eq "$node_expected" ]]; then
    nodes_good=1
  fi
  if [[ "$CONFIG_IMPORT_STATUS" == 已跳过* ]]; then
    OVERALL_STATUS="已跳过"
    return 0
  fi
  if [[ "$PREFLIGHT_FAILED" -eq 1 ]]; then
    OVERALL_STATUS="失败"
    FAIL_REASON="${FAIL_REASON:-预检失败，未执行 site:install}"
    CONFIG_IMPORT_STATUS="失败"
    IMPORT_FAILED=1
    return 0
  fi
  if [[ "$CONFIG_IMPORT_STATUS" == 失败：* ]]; then
    OVERALL_STATUS="失败"
    FAIL_REASON="${FAIL_REASON:-$CONFIG_IMPORT_STATUS}"
    IMPORT_FAILED=1
    CIM_JUDGED_OK=0
    return 0
  fi
  if [[ "$CIM_JUDGED_OK" -ne 1 || "$IMPORT_FAILED" -eq 1 ]]; then
    OVERALL_STATUS="失败"
    FAIL_REASON="${FAIL_REASON:-cim 未判定成功}"
    CONFIG_IMPORT_STATUS="失败"
    IMPORT_FAILED=1
    return 0
  fi
  if [[ "$nodes_good" -ne 1 ]]; then
    why="node 类型数量不符（数据库 ${node_actual}，config/sync ${node_expected}）"
  fi
  if [[ "$http_good" -ne 1 ]]; then
    if [[ -n "$why" ]]; then
      why="${why}；"
    fi
    why="${why}首页 HTTP ${http_code}"
  fi
  if [[ ! "$CONFIG_DIFF_COUNT" =~ ^[0-9]+$ ]]; then
    if [[ -n "$why" ]]; then
      why="${why}；"
    fi
    why="${why}未能统计 config:status 差异"
  fi
  if [[ -n "$why" ]]; then
    OVERALL_STATUS="失败"
    FAIL_REASON="$why"
    CONFIG_IMPORT_STATUS="失败"
    IMPORT_FAILED=1
    return 0
  fi
  if [[ "$CONFIG_DIFF_COUNT" == "0" ]]; then
    OVERALL_STATUS="成功"
    CONFIG_IMPORT_STATUS="成功"
    IMPORT_FAILED=0
    FAIL_REASON=""
    return 0
  fi
  OVERALL_STATUS="部分成功"
  CONFIG_IMPORT_STATUS="部分成功"
  IMPORT_FAILED=0
  FAIL_REASON=""
  log_partial_success_details || true
  return 0
}
ensure_theme() {
  local current
  if ! run_drush theme:install xedc -y; then
    warn "安装主题 xedc 时返回错误。若配置导入已经安装该主题，可以忽略。"
  fi
  current=$(run_drush config:get system.theme default --format=string | tr -d '[:space:]')
  if [[ "$current" != "xedc" ]]; then
    log "配置未把 xedc 设为默认主题，现在写入 system.theme:default。"
    run_drush config:set system.theme default xedc -y
  else
    log "默认主题已是 xedc。"
  fi
}

po_lang() {
  local base="$1"
  if [[ "$base" =~ ^([a-z]{2}(-[a-z]{2,8})?)\.po$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ \.([a-z]{2}(-[a-z]{2,8})?)\.po$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ^([a-z]{2}(-[a-z]{2,8})?)\. ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

language_enabled() {
  local lang="$1"
  local out
  out=$(run_drush php:eval "echo \\Drupal::languageManager()->getLanguage('${lang}') ? 'yes' : 'no';" 2>/dev/null || true)
  [[ "$out" == *yes* ]]
}

import_translations() {
  local file base lang
  local -a files=()
  shopt -s nullglob
  files=("$APP_ROOT"/translations/*.po "$APP_ROOT"/web/themes/custom/xedc/translations/*.po)
  shopt -u nullglob
  if [[ "${#files[@]}" -eq 0 ]]; then
    log "仓库中没有可导入的 .po 文件。"
    return 0
  fi
  log "导入仓库中的翻译文件。"
  for file in "${files[@]}"; do
    base=$(basename "$file")
    if ! lang=$(po_lang "$base"); then
      log "跳过无法识别语言代码的文件：${base}"
      continue
    fi
    if ! language_enabled "$lang"; then
      warn "语言 ${lang} 未启用，跳过 ${base}。"
      continue
    fi
    if run_drush locale:import "$lang" "$file" --type=customized --override=all -y; then
      log "已导入 ${base}（${lang}）。"
    else
      warn "导入 ${base} 失败，继续处理其余翻译。"
    fi
  done
}

validate_sync_yaml() {
  log "校验 config/sync 中的 YAML 均可解析。"
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    APP_ROOT="$APP_ROOT" python3 <<'PY'
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("python3 无法导入 yaml。\n")
    sys.exit(2)

root = Path(os.environ["APP_ROOT"]) / "config" / "sync"
errors = []
count = 0
for path in sorted(root.rglob("*.yml")):
    count += 1
    try:
        with path.open("r", encoding="utf-8") as handle:
            yaml.safe_load(handle)
    except Exception as exc:
        errors.append(f"{path.relative_to(root)}: {exc}")
if errors:
    sys.stderr.write("YAML 解析失败，中止域名替换：\n")
    for item in errors:
        sys.stderr.write(f"错误: {item}\n")
    sys.exit(1)
print(f"已用 python3 yaml 校验 {count} 个文件。")
PY
    return
  fi
  log "python3 没有 yaml 模块，改用 PHP Symfony Yaml 校验。不使用 drush cim --diff。"
  APP_ROOT="$APP_ROOT" php <<'PHP'
<?php
declare(strict_types=1);

$appRoot = getenv('APP_ROOT') ?: '';
$sync = $appRoot . '/config/sync';
if ($appRoot === '' || !is_dir($sync)) {
    fwrite(STDERR, "缺少 config/sync，无法校验 YAML。\n");
    exit(1);
}
require $appRoot . '/vendor/autoload.php';

use Symfony\Component\Yaml\Exception\ParseException;
use Symfony\Component\Yaml\Yaml;

$errors = [];
$count = 0;
$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($sync, FilesystemIterator::SKIP_DOTS));
foreach ($iterator as $file) {
    if (!$file->isFile() || !str_ends_with($file->getFilename(), '.yml')) {
        continue;
    }
    $count++;
    try {
        Yaml::parseFile($file->getPathname());
    } catch (ParseException $exception) {
        $relative = substr($file->getPathname(), strlen($sync) + 1);
        $errors[] = $relative . '：' . $exception->getMessage();
    }
}
if ($errors !== []) {
    fwrite(STDERR, "YAML 解析失败，中止域名替换：\n");
    foreach ($errors as $error) {
        fwrite(STDERR, "错误: {$error}\n");
    }
    exit(1);
}
echo "已用 PHP Symfony Yaml 校验 {$count} 个文件。\n";
PHP
}

rewrite_site_urls() {
  local backup
  log "在 git clone 的工作副本上替换 config/sync 里本站旧域名。解析失败则中止并恢复。"
  backup=$(mktemp -d /tmp/xedc-sync-backup.XXXXXX) || {
    URL_REWRITE_STATUS="已中止（无法创建备份目录）"
    warn "无法创建 config/sync 备份目录，已中止域名替换。"
    return 1
  }
  if ! cp -a "$APP_ROOT/config/sync/." "$backup/"; then
    URL_REWRITE_STATUS="已中止（无法备份，未改文件）"
    warn "无法备份 config/sync，已中止域名替换，未改文件。"
    rm -rf "$backup"
    return 1
  fi
  if ! rewrite_site_urls_apply || ! validate_sync_yaml; then
    warn "域名替换已中止，正在把 config/sync 恢复为替换前的内容。"
    rm -rf "$APP_ROOT/config/sync"
    mkdir -p "$APP_ROOT/config/sync"
    if ! cp -a "$backup/." "$APP_ROOT/config/sync/"; then
      URL_REWRITE_STATUS="已中止（替换失败，且恢复 config/sync 失败，备份在 ${backup}）"
      warn "恢复 config/sync 失败。备份仍在 ${backup}。"
      return 1
    fi
    rm -rf "$backup"
    URL_REWRITE_STATUS="已中止（YAML 无法解析或替换出错，已恢复原文件）"
    return 1
  fi
  rm -rf "$backup"
  URL_REWRITE_STATUS="已完成"
  return 0
}

rewrite_site_urls_apply() {
  log "导入前改写 config/sync：只替换与旧站点域名完全相同的绝对地址、站点邮箱和主机名。"
  log "不替换子域上的外部统计、SMTP 服务器、外部邮箱，以及 Drupal.org、oEmbed、IndexNow 等第三方地址。"
  APP_ROOT="$APP_ROOT" PUBLIC_BASE="$PUBLIC_BASE" php <<'PHP'
<?php
declare(strict_types=1);

$appRoot = getenv('APP_ROOT') ?: '';
$publicBase = getenv('PUBLIC_BASE') ?: '';
$sync = $appRoot . '/config/sync';
$baseParts = parse_url($publicBase);
$newHost = strtolower((string) ($baseParts['host'] ?? ''));
$newScheme = (string) ($baseParts['scheme'] ?? 'http');
if ($appRoot === '' || $newHost === '' || !is_dir($sync)) {
    fwrite(STDERR, "缺少 APP_ROOT、PUBLIC_BASE 或 config/sync，中止域名替换。\n");
    exit(1);
}
require $appRoot . '/vendor/autoload.php';

use Symfony\Component\Yaml\Exception\ParseException;
use Symfony\Component\Yaml\Yaml;

$denySuffixes = [
    'drupal.org', 'google.com', 'gmail.com', 'googleapis.com', 'gstatic.com',
    'github.com', 'githubusercontent.com', 'bing.com', 'yandex.com', 'naver.com',
    'seznam.cz', 'yep.com', 'indexnow.org', 'oembed.com', 'schema.org', 'w3.org',
    'youtube.com', 'youtu.be', 'vimeo.com', 'twitter.com', 'x.com', 'facebook.com',
];

function host_denied(string $host, array $suffixes): bool {
    $host = strtolower($host);
    foreach ($suffixes as $suffix) {
        if ($host === $suffix || str_ends_with($host, '.' . $suffix)) {
            return true;
        }
    }
    return false;
}

function is_site_host(string $host, string $oldHost): bool {
    $host = strtolower($host);
    return $host === $oldHost || $host === 'www.' . $oldHost;
}

function looks_serialized(string $value): bool {
    return (bool) preg_match('/^(?:N;|b:[01];|i:-?\d+;|d:|s:\d+:"|a:\d+:\{|O:\d+:"|C:\d+:")/', $value);
}

function replace_plain(string $value, string $oldHost, string $newScheme, string $newHost): string {
    $value = preg_replace_callback(
        '#\bhttps?://[^\s\'"<>)]+#i',
        static function (array $match) use ($oldHost, $newScheme, $newHost): string {
            $url = $match[0];
            $bits = parse_url($url);
            if (!is_array($bits) || empty($bits['host']) || !is_site_host((string) $bits['host'], $oldHost)) {
                return $url;
            }
            $path = $bits['path'] ?? '';
            $query = isset($bits['query']) ? '?' . $bits['query'] : '';
            $fragment = isset($bits['fragment']) ? '#' . $bits['fragment'] : '';
            return $newScheme . '://' . $newHost . $path . $query . $fragment;
        },
        $value
    ) ?? $value;
    $pattern = '/(?<![A-Za-z0-9._%+-])([A-Za-z0-9._%+-]+)@' . preg_quote($oldHost, '/') . '(?![A-Za-z0-9.-])/i';
    $value = preg_replace($pattern, '$1@' . $newHost, $value) ?? $value;
    if (is_site_host($value, $oldHost)) {
        return $newHost;
    }
    return $value;
}

function map_data(mixed $data, string $oldHost, string $newScheme, string $newHost): mixed {
    if (is_array($data)) {
        foreach ($data as $key => $item) {
            $data[$key] = map_data($item, $oldHost, $newScheme, $newHost);
        }
        return $data;
    }
    if (is_string($data)) {
        return replace_plain($data, $oldHost, $newScheme, $newHost);
    }
    return $data;
}

function transform_leaf(string $value, string $oldHost, string $newScheme, string $newHost): string {
    if (looks_serialized($value)) {
        $decoded = @unserialize($value, ['allowed_classes' => false]);
        if ($decoded !== false || $value === 'b:0;') {
            return serialize(map_data($decoded, $oldHost, $newScheme, $newHost));
        }
    }
    return replace_plain($value, $oldHost, $newScheme, $newHost);
}

function walk_strings(mixed $data, callable $visitor): void {
    if (is_array($data)) {
        foreach ($data as $item) {
            walk_strings($item, $visitor);
        }
        return;
    }
    if (is_string($data)) {
        $visitor($data);
    }
}

function yaml_host(string $file, string $key): string {
    if (!is_file($file)) {
        return '';
    }
    try {
        $data = Yaml::parseFile($file);
    } catch (ParseException) {
        return '';
    }
    if (!is_array($data)) {
        return '';
    }
    $value = $data[$key] ?? '';
    if ($key === 'mail' && is_string($value) && str_contains($value, '@')) {
        return strtolower((string) substr(strrchr($value, '@'), 1));
    }
    if (!is_string($value) || $value === '') {
        return '';
    }
    $host = parse_url($value, PHP_URL_HOST);
    return is_string($host) ? strtolower($host) : '';
}

$oldHost = yaml_host($sync . '/simple_sitemap.settings.yml', 'base_url');
if ($oldHost === '' || strcasecmp($oldHost, $newHost) === 0 || host_denied($oldHost, $denySuffixes)) {
    $mailHost = yaml_host($sync . '/system.site.yml', 'mail');
    if ($mailHost !== '' && strcasecmp($mailHost, $newHost) !== 0 && !host_denied($mailHost, $denySuffixes)) {
        $oldHost = $mailHost;
    }
}
if ($oldHost === '' || strcasecmp($oldHost, $newHost) === 0) {
    echo "未发现需要替换的旧站点域名，配置中的绝对地址保持不变。\n";
    exit(0);
}

echo "旧站点域名：{$oldHost}\n";
echo "新站点地址：{$newScheme}://{$newHost}\n";

$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($sync, FilesystemIterator::SKIP_DOTS));
$changed = [];
$skippedHosts = [];
foreach ($iterator as $fileInfo) {
    if (!$fileInfo->isFile() || !str_ends_with($fileInfo->getFilename(), '.yml')) {
        continue;
    }
    $path = $fileInfo->getPathname();
    $relative = 'config/sync/' . substr($path, strlen($sync) + 1);
    try {
        $parsed = Yaml::parseFile($path);
    } catch (ParseException $exception) {
        fwrite(STDERR, "配置无法解析，中止域名替换 {$relative}：{$exception->getMessage()}\n");
        exit(1);
    }
    $original = file_get_contents($path);
    if ($original === false) {
        fwrite(STDERR, "无法读取 {$relative}，中止域名替换。\n");
        exit(1);
    }
    walk_strings($parsed, static function (string $value) use ($oldHost, $relative, &$skippedHosts, $denySuffixes): void {
        if (preg_match_all('#\bhttps?://([^/\s\'"<>)]+)#i', $value, $matches)) {
            foreach ($matches[1] as $host) {
                $host = strtolower(preg_replace('/:\d+$/', '', $host) ?? $host);
                if (!is_site_host($host, $oldHost)) {
                    $skippedHosts[$host][$relative] = true;
                }
            }
        }
        if (preg_match_all('/[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/', $value, $emails)) {
            foreach ($emails[1] as $domain) {
                $domain = strtolower($domain);
                if (!is_site_host($domain, $oldHost)) {
                    $skippedHosts[$domain][$relative] = true;
                }
            }
        }
    });
    $replacements = [];
    walk_strings($parsed, static function (string $value) use (&$replacements, $oldHost, $newScheme, $newHost): void {
        $newValue = transform_leaf($value, $oldHost, $newScheme, $newHost);
        if ($newValue !== $value && (str_contains($value, '://') || str_contains($value, '@') || looks_serialized($value))) {
            $replacements[$value] = $newValue;
        }
    });
    uksort($replacements, static fn(string $a, string $b): int => strlen($b) <=> strlen($a));
    $updated = $original;
    foreach ($replacements as $old => $new) {
        $updated = str_replace($old, $new, $updated);
    }
    $updated = preg_replace(
        '/(?<![A-Za-z0-9.-])(?:www\.)?' . preg_quote($oldHost, '/') . '(?![A-Za-z0-9.-])/i',
        $newHost,
        $updated
    ) ?? $updated;
    if ($updated === $original) {
        continue;
    }
    try {
        $check = Yaml::parse($updated);
    } catch (ParseException $exception) {
        fwrite(STDERR, "改写后的 YAML 无法解析，中止域名替换 {$relative}：{$exception->getMessage()}\n");
        exit(1);
    }
    $serializedOk = true;
    walk_strings($check, static function (string $value) use (&$serializedOk): void {
        if (looks_serialized($value)) {
            $decoded = @unserialize($value, ['allowed_classes' => false]);
            if ($decoded === false && $value !== 'b:0;') {
                $serializedOk = false;
            }
        }
    });
    if (!$serializedOk) {
        fwrite(STDERR, "序列化字段无法还原，中止域名替换 {$relative}。\n");
        exit(1);
    }
    if (file_put_contents($path, $updated) === false) {
        fwrite(STDERR, "无法写入 {$relative}\n");
        exit(1);
    }
    $changed[] = $relative;
}

if ($changed === []) {
    echo "没有配置文件需要改写。\n";
} else {
    echo "已改写本站地址的配置：\n";
    foreach ($changed as $relative) {
        echo "  - {$relative}\n";
    }
}
if ($skippedHosts !== []) {
    echo "保留未改的外部主机或邮箱域名：\n";
    ksort($skippedHosts);
    foreach ($skippedHosts as $host => $files) {
        $names = array_keys($files);
        sort($names);
        echo "  - {$host}（" . implode(', ', $names) . "）\n";
    }
}
PHP
}

verify_site_base_url() {
  local current
  current=$(run_drush config:get simple_sitemap.settings base_url --format=string 2>/dev/null | tr -d '[:space:]' || true)
  if [[ "$current" == "$PUBLIC_BASE" ]]; then
    log "simple_sitemap.settings:base_url 已是 ${PUBLIC_BASE}。"
    return 0
  fi
  if run_drush config:set simple_sitemap.settings base_url "$PUBLIC_BASE" -y; then
    log "导入后补写 simple_sitemap.settings:base_url=${PUBLIC_BASE}。"
  else
    warn "未能确认 sitemap base_url，请手动检查。"
  fi
}

install_cron() {
  cat >/etc/cron.d/xedc-drupal <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Drupal cron, including Scheduler. Managed by install-restore.sh.
*/15 * * * * ${WEB_USER} /usr/bin/php ${APP_ROOT}/vendor/bin/drush --root=${APP_ROOT}/web --uri=${PUBLIC_BASE} cron -q
EOF
  chmod 644 /etc/cron.d/xedc-drupal
  log "已安装 cron：每 15 分钟以 ${WEB_USER} 运行 drush cron。"
}

write_acceptance() {
  local saved_text saved_block boot raw http_code node_list node_actual node_expected
  if [[ "${ACCEPTANCE_READY:-0}" -ne 1 || "${ACCEPTANCE_DONE:-0}" -eq 1 ]]; then
    return 0
  fi
  saved_text="${FIRST_ERROR_TEXT:-}"
  saved_block="${FIRST_ERROR_BLOCK:-}"
  boot="Failed"
  if [[ -n "${DRUSH_BIN:-}" && -x "$DRUSH_BIN" && -d "${APP_ROOT:-}" ]]; then
    set +e
    raw=$(run_drush status --field=bootstrap)
    set -e
    boot=$(printf '%s\n' "$raw" | awk '{
      gsub(/\r/, "")
      if ($0 == "Successful" || $0 == "Failed") { value = $0 }
    } END { print value }')
    if [[ "$boot" != "Successful" ]]; then
      boot="Failed"
    fi
  fi
  node_list="无"
  node_actual="未统计"
  if [[ -n "${SQL_BIN:-}" && -n "${DB_NAME:-}" ]]; then
    set +e
    node_list=$("$SQL_BIN" --protocol=socket --batch --skip-column-names --user=root -e "SELECT type FROM \`${DB_NAME}\`.node_type ORDER BY type" 2>/dev/null | paste -sd, -)
    set -e
    if [[ -n "$node_list" ]]; then
      node_actual=$(printf '%s\n' "$node_list" | awk -F',' '{ print NF }')
    else
      node_list="无"
      node_actual=0
    fi
  fi
  if [[ -d "${APP_ROOT:-}/config/sync" ]]; then
    node_expected=$(node_type_yml_count)
  else
    node_expected="未统计"
  fi
  NODE_TYPE_ACTUAL="$node_actual"
  NODE_TYPE_EXPECTED="$node_expected"
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 15 http://127.0.0.1 -H "Host: ${DOMAIN}" || true)
  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    http_code="000"
  fi
  if [[ "$http_code" =~ ^5[0-9][0-9]$ ]]; then
    capture_http_error_excerpt || true
  fi
  if [[ "$CIM_JUDGED_OK" -eq 1 && "$IMPORT_FAILED" -eq 0 ]]; then
    collect_config_diffs || true
  fi
  decide_overall_status "$http_code" "$node_actual" "$node_expected"
  ACCEPTANCE_SUMMARY="验收：bootstrap=${boot}  配置差异=${CONFIG_DIFF_COUNT}  node类型=${node_list}  首页HTTP=${http_code}  整体=${OVERALL_STATUS}"
  if [[ -n "${INSTALL_LOG:-}" && -f "$INSTALL_LOG" ]]; then
    {
      echo ""
      echo "===== acceptance ====="
      printf '%s\n' "$ACCEPTANCE_SUMMARY"
      printf '整体=%s\n' "$OVERALL_STATUS"
      printf '配置导入=%s\n' "$CONFIG_IMPORT_STATUS"
      printf 'node类型数量=%s/%s\n' "$node_actual" "$node_expected"
      if [[ -n "${FAIL_REASON:-}" ]]; then
        printf '原因=%s\n' "$FAIL_REASON"
      fi
    } >>"$INSTALL_LOG"
  fi
  rm -rf /tmp/xedc-cex
  ACCEPTANCE_DONE=1
  FIRST_ERROR_TEXT="$saved_text"
  FIRST_ERROR_BLOCK="$saved_block"
}

print_acceptance_line() {
  if [[ "${ACCEPTANCE_READY:-0}" -ne 1 ]]; then
    return 0
  fi
  write_acceptance || true
  if [[ "${ACCEPTANCE_PRINTED:-0}" -eq 1 || -z "${ACCEPTANCE_SUMMARY:-}" ]]; then
    return 0
  fi
  printf '%s\n' "$ACCEPTANCE_SUMMARY"
  ACCEPTANCE_PRINTED=1
}

write_credentials() {
  local admin_line revision
  if [[ "${CREDENTIALS_WRITTEN:-0}" -eq 1 ]]; then
    return 0
  fi
  if [[ -z "${DB_PASS:-}" && -z "${DRUPAL_ADMIN_PASS:-}" ]]; then
    return 0
  fi
  if [[ "${DID_INSTALL:-0}" -eq 1 && -n "${DRUPAL_ADMIN_PASS:-}" ]]; then
    admin_line="管理员口令：${DRUPAL_ADMIN_PASS}"
  elif [[ -n "${DRUPAL_ADMIN_PASS:-}" ]]; then
    admin_line="管理员口令：${DRUPAL_ADMIN_PASS}（已生成；若站点安装未完成，该口令可能尚未写入数据库）"
  else
    admin_line="管理员口令：本次未重新安装站点，沿用数据库中的现有口令。"
  fi
  revision="尚未克隆"
  if [[ -d "${APP_ROOT:-}/.git" ]]; then
    revision=$(git -C "$APP_ROOT" rev-parse HEAD 2>/dev/null || true)
    revision=${revision:-未知}
  fi
  umask 077
  if ! {
    cat <<EOF
生成时间：$(date '+%F %T')
站点地址：${PUBLIC_BASE:-尚未配置}
代码目录：${APP_ROOT:-未知}
Git 提交：${revision}
数据库主机：${DB_HOST:-localhost}:${DB_PORT:-3306}
数据库名：${DB_NAME:-}
数据库用户：${DB_USER:-}
数据库口令：${DB_PASS:-未生成}
管理员用户：${DRUPAL_ADMIN_USER:-admin}
${admin_line}
登录路径：${PUBLIC_BASE:-}/user/login
配置预检：${PREFLIGHT_STATUS}
配置导入：${CONFIG_IMPORT_STATUS}
整体：${OVERALL_STATUS}
失败原因：${FAIL_REASON:-无}
配置差异：${CONFIG_DIFF_COUNT}
node类型数量：${NODE_TYPE_ACTUAL:-未统计}/${NODE_TYPE_EXPECTED:-未统计}
域名替换：${URL_REWRITE_STATUS}
安装日志：${INSTALL_LOG}
EOF
    if [[ -n "${PREFLIGHT_ERRORS:-}" ]]; then
      printf '\n预检详情：\n%s\n' "$PREFLIGHT_ERRORS"
    fi
    if [[ -n "${SELF_HEAL_RECORD:-}" ]]; then
      printf '\n自愈记录：\n%s\n' "$SELF_HEAL_RECORD"
    fi
    if [[ "$OVERALL_STATUS" == "失败" && -n "${FIRST_ERROR_BLOCK:-}" ]]; then
      printf '\n第一条错误原文：\n%s\n' "$FIRST_ERROR_BLOCK"
    fi
    if [[ -n "${PLAN_DETAIL:-}" ]]; then
      printf '\n导入计划：\n%s\n' "$PLAN_DETAIL"
    fi
    if [[ -n "${HTTP_ERROR_EXCERPT:-}" ]]; then
      printf '\n首页错误：\n%s\n' "$HTTP_ERROR_EXCERPT"
    fi
    if [[ -n "${ACCEPTANCE_SUMMARY:-}" ]]; then
      printf '\n%s\n' "$ACCEPTANCE_SUMMARY"
    fi
  } >"$CREDENTIALS_FILE"
  then
    warn "无法写入凭据文件 ${CREDENTIALS_FILE}。"
    return 1
  fi
  chmod 600 "$CREDENTIALS_FILE" || true
  CREDENTIALS_WRITTEN=1
  log "连接信息已写入 ${CREDENTIALS_FILE}（权限 600）。"
}

print_summary() {
  log "恢复流程结束。"
  cat <<EOF

站点地址：${PUBLIC_BASE}
代码目录：${APP_ROOT}
当前提交：$(git -C "$APP_ROOT" log -1 --pretty='%h %s' 2>/dev/null || echo 未知)
Drupal：11.4.11（composer.lock）
默认主题：xedc
配置目录：${APP_ROOT}/config/sync
凭据文件：${CREDENTIALS_FILE}
EOF
  if [[ -n "$BACKUP_PATH" ]]; then
    printf '旧目录备份：%s\n确认新站点可用后可手动删除该备份。\n' "$BACKUP_PATH"
  fi
  if [[ "$SSL_FAILED" -eq 1 ]]; then
    printf '\nHTTPS 证书没有申请成功，当前仅配置了 HTTP。\n'
  fi
  if [[ -n "${FAIL_REASON:-}" ]]; then
    printf '\n原因：%s\n' "$FAIL_REASON"
  fi
  printf '\n整体：%s\n配置导入：%s\n' "$OVERALL_STATUS" "$CONFIG_IMPORT_STATUS"
  if [[ "$PREFLIGHT_FAILED" -eq 1 ]]; then
    printf '\n配置预检未通过，已阻止 site:install。具体错误见上方输出和凭据文件。\n'
  elif [[ "$OVERALL_STATUS" == "失败" || "$IMPORT_FAILED" -eq 1 ]]; then
    printf '\n配置导入失败。状态：%s。请根据 %s 检查后重新执行本脚本。\n' "$CONFIG_IMPORT_STATUS" "$INSTALL_LOG"
  elif [[ "$OVERALL_STATUS" == "部分成功" ]]; then
    printf '\n部分成功。配置差异 %s 项，分布与名单见 %s。\n' "$CONFIG_DIFF_COUNT" "$INSTALL_LOG"
  fi
  if [[ "$REWRITE_FAILED" -eq 1 ]]; then
    printf '\n域名替换已中止，config/sync 已按替换前内容恢复。\n'
  fi
  if [[ "$URL_REWRITE_STATUS" == "已完成" ]]; then
    printf '\n本站绝对地址已按本次域名改写。外部统计、SMTP 服务器和外部邮箱保持原配置，请核对日志。\n'
  fi
  cat <<'EOF'

建议立即检查：首页、/user/login、管理主题、语言切换、静态资源是否 200。
本脚本没有恢复用户内容、上传文件或原数据库。
EOF
  print_acceptance_line
}

preflight_database() {
  if command -v mariadb >/dev/null 2>&1; then
    SQL_BIN=mariadb
  elif command -v mysql >/dev/null 2>&1; then
    SQL_BIN=mysql
  else
    log "尚未安装 MariaDB 客户端，安装软件包后再检查数据库。"
    return 0
  fi
  if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
    log "MariaDB 尚未运行，安装软件包后再检查数据库。"
    return 0
  fi
  assert_database_safe
}

main() {
  parse_args "$@"
  require_root
  check_os
  validate_inputs
  if [[ -e "$APP_ROOT" && "$ASSUME_YES" -ne 1 ]]; then
    die "目录 ${APP_ROOT} 已存在。确认把该目录整份备份并重新克隆最新代码后，再追加 --yes。在此之前不会安装软件包，也不会重启数据库或 Web 服务。"
  fi
  preflight_database
  log "开始恢复。仓库：${GIT_REPO}，分支：${GIT_BRANCH}，目录：${APP_ROOT}，域名：${DOMAIN}。"
  ACCEPTANCE_READY=1
  prepare_install_log || true
  log "风险提示：将用仓库中的 config/sync 执行 site:install --existing-config。它可能与原站点实际运行配置不一致；不恢复用户内容、上传文件和数据库数据。"
  install_packages
  systemctl enable --now "$DB_SERVICE"
  assert_database_safe
  configure_php
  configure_mariadb
  clone_repository
  self_heal_config_sync
  ensure_sync_htaccess
  composer_install
  build_theme
  apply_database
  if [[ "$REINSTALL" -eq 1 ]]; then
    DID_INSTALL=0
    SITE_HAS_CONTENT=0
  fi
  prepare_directories
  write_settings
  fix_permissions writable-settings
  configure_nginx
  if [[ "$SITE_HAS_CONTENT" -eq 1 ]]; then
    log "已有真实站点且未传入 --reinstall，跳过 site:install 与配置导入，不改动已有数据。"
    CONFIG_IMPORT_STATUS="已跳过（站点已有内容，未改动数据）"
    OVERALL_STATUS="已跳过"
    ensure_config_sync_directory
  else
    if ! rewrite_site_urls; then
      REWRITE_FAILED=1
      warn "域名替换已中止。后续安装将使用恢复后的 config/sync。"
    fi
    config_preflight
    finish_config_preflight
    if [[ "$PREFLIGHT_FAILED" -eq 1 ]]; then
      CONFIG_IMPORT_STATUS="预检失败"
      IMPORT_FAILED=1
      FAIL_REASON="预检失败，未执行 site:install"
      OVERALL_STATUS="失败"
      warn "预检失败，已阻止 site:install。继续权限、cron、凭据与验收。"
    elif [[ "$REINSTALL" -eq 1 ]] || ! site_installed; then
      if [[ -z "$DRUPAL_ADMIN_PASS" ]]; then
        DRUPAL_ADMIN_PASS=$(random_secret 24)
      fi
      run_site_install_existing
      write_settings
      fix_permissions writable-settings
      import_config_with_retries
    else
      log "检测到已安装、且没有真实内容的站点，跳过 drush site:install，继续 drush cim。"
      import_config_with_retries
    fi
    ensure_config_sync_directory
    if [[ "$PREFLIGHT_FAILED" -eq 1 ]]; then
      log_skipped_followups "${FAIL_REASON:-预检失败，未执行 site:install}"
    elif [[ "$CIM_JUDGED_OK" -eq 1 && "$IMPORT_FAILED" -eq 0 ]]; then
      ensure_theme || warn "确认默认主题时出错，请稍后手动检查。"
      import_translations || warn "翻译导入未完成。"
      verify_site_base_url || warn "未能确认 sitemap base_url。"
      if ! run_drush cr; then
        warn "drush cr 未成功。"
      fi
      finalize_config_status
    else
      log_skipped_followups "${FAIL_REASON:-cim 未判定成功}"
    fi
  fi
  fix_permissions || warn "收尾权限调整未完全成功。"
  ensure_sync_htaccess || warn "未能写入 config/sync/.htaccess。"
  install_cron || warn "未能安装 cron。"
  write_acceptance || true
  write_credentials || warn "凭据文件未能写入。"
  run_drush status --fields=bootstrap,drupal-version,db-status,uri || true
  print_summary
  if [[ "$SSL_FAILED" -eq 1 || "$IMPORT_FAILED" -eq 1 || "$PREFLIGHT_FAILED" -eq 1 || "$REWRITE_FAILED" -eq 1 || "$OVERALL_STATUS" == "失败" ]]; then
    exit 1
  fi
}

main "$@"
