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
#    本脚本在空站点上执行 drush cim -y，有差异也会继续导入。
#    导入结果以仓库中的 config/sync 为准，不保证与原生产环境完全一致。
# 2. 导入前会把本站自己的绝对地址改成本次域名，包括：
#    simple_sitemap 的 base_url、Metatag 里指向本站的 http(s) URL（含序列化字段）、
#    @旧域名 的站点邮箱，以及与旧域名完全相同的主机名（如 smtp_client_hostname）。
#    不替换子域上的外部统计（例如 Matomo）、SMTP 服务器、外部邮箱、Drupal.org、
#    oEmbed 和搜索引擎 IndexNow。这些会在日志里列出。脚本不打印配置中的口令。
# 3. 每次运行都会重新 git clone 指定分支的最新提交。目标目录已存在时，
#    先整目录改名备份，再克隆。备份里可能有旧的上传文件，新站点不会使用它们。
# 4. 仅当显式传入 --reinstall --yes 时才会删除已有数据库。
#    若库里已有节点或除管理员以外的用户，且未同时传入这两个参数，脚本会拒绝继续。
# 5. 始终使用 composer install 安装 composer.lock 中锁定的版本，不执行 composer update。
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
DID_INSTALL=0
PUBLIC_BASE=""
HASH_SALT=""
SQL_BIN=""
DB_SERVICE=""
DRUSH_BIN=""
SERVER_NAMES=""
BACKUP_PATH=""

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
  printf '\n[%s] 警告: %s\n' "$(date '+%F %T')" "$*" >&2
}

die() {
  printf '\n[%s] 错误: %s\n' "$(date '+%F %T')" "$*" >&2
  exit 1
}

trap 'rc=$?; printf "\n[错误] 第 %s 行失败（状态 %s）：%s\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; if [[ -n "${BACKUP_PATH:-}" ]]; then printf "旧目录备份仍在：%s\n" "$BACKUP_PATH" >&2; fi' ERR

usage() {
  cat <<'EOF'
用法：sudo ./install-restore.sh [域名] [选项]

在 Ubuntu 24.04 或 26.04 上安装运行环境，克隆 https://github.com/xxedc/drupal 的最新代码，
按 composer.lock 安装 Drupal 11.4.11，构建 xedc 主题，安装空站点并导入 config/sync。
导入前会把配置里属于本站的绝对地址改成本次域名，并保留第三方服务地址。

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

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "安装基础软件包与 PHP 8.5。"
  apt-get update
  apt-get install -y \
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
    apt-get update
  else
    log "软件源已提供 PHP 8.5，不再重复添加 PPA。"
  fi
  if ! apt-cache show php8.5-cli >/dev/null 2>&1; then
    die "Ubuntu ${VERSION_ID:-unknown} 的软件源中没有 php8.5-cli。请确认 ondrej/php 已支持该版本。"
  fi
  apt-get install -y \
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
  local exists users_table real_users node_count
  exists=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'")
  if [[ "$exists" -eq 0 ]]; then
    log "数据库 ${DB_NAME} 尚不存在，稍后会创建空库。"
    return 0
  fi
  users_table=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='users_field_data'")
  if [[ "$users_table" -eq 0 ]]; then
    local any_tables
    any_tables=$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")
    if [[ "$any_tables" -gt 0 && "$REINSTALL" -ne 1 ]]; then
      die "数据库 ${DB_NAME} 非空，但不是可识别的 Drupal 站点。请换一个空库，或同时传入 --reinstall --yes 以删除该库。"
    fi
    if [[ "$any_tables" -gt 0 && "$ASSUME_YES" -ne 1 ]]; then
      die "将删除非空数据库 ${DB_NAME}。请同时传入 --reinstall --yes。"
    fi
    return 0
  fi

  real_users=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.users_field_data WHERE uid>0")
  node_count=0
  if [[ "$(sql_scalar_required "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='node'")" -ge 1 ]]; then
    node_count=$(sql_scalar_required "SELECT COUNT(*) FROM \`${DB_NAME}\`.node")
  fi
  if [[ "$real_users" -gt 1 || "$node_count" -gt 0 ]]; then
    if [[ "$REINSTALL" -ne 1 || "$ASSUME_YES" -ne 1 ]]; then
      die "数据库 ${DB_NAME} 已有内容（用户 ${real_users}，节点 ${node_count}）。本脚本不恢复用户数据，也不会在含内容的库上导入配置。若确认删除该库并安装空站点，请同时传入 --reinstall --yes。"
    fi
    warn "将按 --reinstall --yes 删除数据库 ${DB_NAME} 中的全部数据。"
    return 0
  fi

  if [[ "$REINSTALL" -eq 1 ]]; then
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      die "重新安装会删除数据库 ${DB_NAME}。请同时传入 --yes。"
    fi
    warn "数据库 ${DB_NAME} 将按 --reinstall 删除并重建。"
  else
    log "数据库 ${DB_NAME} 已有空站点（无节点、无额外用户），将跳过 site:install，并重新导入 config/sync。"
  fi
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
  local host
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
    CONFIG_SYNC="$APP_ROOT/config/sync" \
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
$block .= "\$settings['config_sync_directory'] = " . var_export((string) getenv('CONFIG_SYNC'), true) . ";\n";
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
  (
    cd "$APP_ROOT"
    runuser -u "$WEB_USER" -- env HOME=/tmp "$DRUSH_BIN" --root="$APP_ROOT/web" --uri="$PUBLIC_BASE" "$@"
  )
}

urlencode() {
  php -r 'echo rawurlencode($argv[1]);' "$1"
}

install_site() {
  local db_url
  db_url="mysql://$(urlencode "$DB_USER"):$(urlencode "$DB_PASS")@${DB_HOST}:${DB_PORT}/$(urlencode "$DB_NAME")"
  local -a args=(
    site:install standard -y
    "--site-name=${DRUPAL_SITE_NAME}"
    "--site-mail=${DRUPAL_SITE_MAIL}"
    "--account-name=${DRUPAL_ADMIN_USER}"
    "--account-pass=${DRUPAL_ADMIN_PASS}"
    "--account-mail=${DRUPAL_SITE_MAIL}"
    "--db-url=${db_url}"
  )
  log "执行 Drupal 标准安装（drush site:install standard）。"
  if run_drush "${args[@]}" --locale=zh-hans; then
    DID_INSTALL=1
    return 0
  fi
  if site_installed; then
    warn "中文安装命令返回错误，但数据库里已经有 Drupal 站点，不再清空重装。"
    DID_INSTALL=1
    return 0
  fi
  warn "使用 zh-hans 安装未成功。将清空数据库后改用安装程序默认语言重试；默认语言随后仍由 config/sync 决定。"
  REINSTALL=1
  apply_database
  write_settings
  fix_permissions writable-settings
  run_drush "${args[@]}"
  DID_INSTALL=1
}

import_config() {
  local uuid
  uuid=$(php -r '
    foreach (file($argv[1]) as $line) {
      if (preg_match("/^uuid:\\s*([0-9a-fA-F-]+)/", $line, $matches)) {
        echo $matches[1];
        exit(0);
      }
    }
    exit(1);
  ' "$APP_ROOT/config/sync/system.site.yml")
  log "将站点 UUID 调整为 config/sync 中的 ${uuid}，否则配置导入会被拒绝。"
  run_drush config:set system.site uuid "$uuid" -y
  log "开始导入 ${APP_ROOT}/config/sync。"
  log "提示：仓库配置与当前空站点的标准安装结果不同。drush cim -y 会在存在差异时继续，并以仓库配置为准。这不一定与原生产库完全一致。"
  if ! run_drush cim -y; then
    warn "第一次 drush cim 未成功。这通常是模块刚刚启用。将执行 updatedb 后再次导入。"
    run_drush updatedb -y
    run_drush cim -y
  fi
  run_drush updatedb -y
  run_drush cr
}

ensure_theme() {
  local current
  if ! run_drush theme:enable xedc -y; then
    warn "启用主题 xedc 时返回错误。若配置导入已经启用该主题，可以忽略。"
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

rewrite_site_urls() {
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
    fwrite(STDERR, "缺少 APP_ROOT、PUBLIC_BASE 或 config/sync，已跳过地址替换。\n");
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
        fwrite(STDERR, "跳过无法解析的配置 {$relative}：{$exception->getMessage()}\n");
        continue;
    }
    $original = file_get_contents($path);
    if ($original === false) {
        continue;
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
        fwrite(STDERR, "已放弃改写 {$relative}，YAML 无效：{$exception->getMessage()}\n");
        continue;
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
        fwrite(STDERR, "已放弃改写 {$relative}，序列化字段无法还原。\n");
        continue;
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

write_credentials() {
  local admin_line
  if [[ "$DID_INSTALL" -eq 1 ]]; then
    admin_line="管理员口令：${DRUPAL_ADMIN_PASS}"
  else
    admin_line="管理员口令：本次未重新安装站点，沿用数据库中的现有口令。"
  fi
  umask 077
  cat >"$CREDENTIALS_FILE" <<EOF
生成时间：$(date '+%F %T')
站点地址：${PUBLIC_BASE}
代码目录：${APP_ROOT}
Git 提交：$(git -C "$APP_ROOT" rev-parse HEAD)
数据库主机：${DB_HOST}:${DB_PORT}
数据库名：${DB_NAME}
数据库用户：${DB_USER}
数据库口令：${DB_PASS}
管理员用户：${DRUPAL_ADMIN_USER}
${admin_line}
登录路径：${PUBLIC_BASE}/user/login
EOF
  chmod 600 "$CREDENTIALS_FILE"
  log "连接信息已写入 ${CREDENTIALS_FILE}（权限 600）。"
}

print_summary() {
  log "恢复流程结束。"
  cat <<EOF

站点地址：${PUBLIC_BASE}
代码目录：${APP_ROOT}
当前提交：$(git -C "$APP_ROOT" log -1 --pretty='%h %s')
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
  cat <<'EOF'

建议立即检查：首页、/user/login、管理主题、语言切换、静态资源是否 200。
本站绝对地址已按本次域名改写。外部统计、SMTP 服务器和外部邮箱保持原配置，请核对日志。
本脚本没有恢复用户内容、上传文件或原数据库。
EOF
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
  log "风险提示：将导入仓库中的 config/sync，它可能与原站点实际运行配置不一致；不恢复用户内容、上传文件和数据库数据。"
  install_packages
  systemctl enable --now "$DB_SERVICE"
  assert_database_safe
  configure_php
  configure_mariadb
  clone_repository
  composer_install
  build_theme
  apply_database
  if [[ "$REINSTALL" -eq 1 ]]; then
    DID_INSTALL=0
  fi
  prepare_directories
  write_settings
  fix_permissions writable-settings
  configure_nginx
  if [[ "$REINSTALL" -eq 1 ]] || ! site_installed; then
    if [[ -z "$DRUPAL_ADMIN_PASS" ]]; then
      DRUPAL_ADMIN_PASS=$(random_secret 24)
    fi
    install_site
    write_settings
    fix_permissions writable-settings
  else
    log "检测到已安装且无用户内容的站点，跳过 drush site:install。"
  fi
  rewrite_site_urls
  import_config
  ensure_theme
  import_translations
  verify_site_base_url
  run_drush cr
  fix_permissions
  install_cron
  write_credentials
  run_drush status --fields=bootstrap,drupal-version,db-status,uri || true
  print_summary
  if [[ "$SSL_FAILED" -eq 1 ]]; then
    exit 1
  fi
}

main "$@"
