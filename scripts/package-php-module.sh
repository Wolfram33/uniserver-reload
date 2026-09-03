#!/usr/bin/env bash
# Package an official PHP Windows build as a Uniform Server ZeroXV module.
#
# Usage: package-php-module.sh <branch> [output-dir]
#   e.g. package-php-module.sh 8.4 dist
#
# Downloads the latest thread-safe x64 build of the given PHP branch from
# windows.php.net and repacks it in the layout the UniController expects
# (replicates the structure of the upstream ZeroXV_php_8_3_x modules):
#
#   core/php8X/                  PHP files, ext/ renamed to extensions/
#   core/php8X/php_test.ini      from php.ini-production
#   core/php8X/php_production.ini
#   core/php8X/php_development.ini from php.ini-development
#   core/php8X/php-cli.ini
#   core/apache2/conf/extra_us/php8X.conf   Apache module wiring
#
# The resulting ZIP is unpacked into the UniServerZ root folder.
set -euo pipefail

BRANCH="${1:?usage: package-php-module.sh <branch e.g. 8.4> [output-dir]}"
OUT_DIR="${2:-dist}"
SHORT="php${BRANCH//./}"          # 8.4 -> php84
BASE_URL="https://windows.php.net/downloads/releases"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Fetching release metadata for PHP $BRANCH"
curl -fsSL -o "$WORK/releases.json" "$BASE_URL/releases.json"

VERSION="$(jq -r --arg b "$BRANCH" '.[$b].version // empty' "$WORK/releases.json")"
if [ -z "$VERSION" ]; then
  echo "ERROR: PHP branch $BRANCH not found in releases.json" >&2
  jq -r 'keys[]' "$WORK/releases.json" >&2
  exit 1
fi

# Pick the thread-safe x64 build regardless of compiler version (vs16/vs17/...)
ZIP_PATH="$(jq -r --arg b "$BRANCH" \
  '.[$b] | to_entries[] | select(.key | startswith("ts-") and endswith("-x64")) | .value.zip.path' \
  "$WORK/releases.json" | head -1)"
if [ -z "$ZIP_PATH" ]; then
  echo "ERROR: no thread-safe x64 build found for PHP $BRANCH" >&2
  exit 1
fi

echo "==> Downloading $ZIP_PATH (PHP $VERSION)"
curl -fsSL -o "$WORK/php.zip" "$BASE_URL/$ZIP_PATH"

PHP_ROOT="$WORK/module/core/$SHORT"
mkdir -p "$PHP_ROOT"
unzip -q "$WORK/php.zip" -d "$PHP_ROOT"

if [ ! -f "$PHP_ROOT/php8apache2_4.dll" ]; then
  echo "ERROR: php8apache2_4.dll missing - not a thread-safe build?" >&2
  exit 1
fi

# Uniform Server keeps the extension DLLs in "extensions" instead of "ext"
mv "$PHP_ROOT/ext" "$PHP_ROOT/extensions"

# --- Generate the four ini files the UniController expects -------------------
# ${US_ROOTF} and ${PHP_INI_SELECT} are environment variables set by the
# UniController at runtime; they must remain literal in the generated files.
#
# OPcache: php.ini-production carries ";zend_extension=opcache". That short
# form is enabled here in the php_opcache.dll path form, for two reasons:
# without OPcache every request recompiles every file, and the controller's
# PHP > Accelerator toggle only recognises lines that name php_opcache.dll
# (it never worked for this module before). PHP 8.5+ has OPcache built in
# and ships no such line - nothing to do there. The cache sizes are tuned
# for the bundle by scripts/tune-server-config.ps1.
patch_ini() { # $1=source $2=dest-name $3=variant label
  local dest="$PHP_ROOT/$2"
  cp "$1" "$dest"
  sed -i \
    -e 's|^;include_path = ".;c:\\php\\includes"|include_path = ".;${US_ROOTF}/home/us_pear/PEAR"|' \
    -e 's|^;user_dir *=.*$|user_dir = "${US_ROOTF}/www"|' \
    -e 's|^;extension_dir = "ext"|extension_dir = "${US_ROOTF}/core/'"$SHORT"'/extensions"|' \
    -e 's|^;upload_tmp_dir *=.*$|upload_tmp_dir = ${US_ROOTF}/tmp|' \
    -e 's|^;date.timezone *=.*$|date.timezone = "Europe/London"|' \
    -e 's|^;sendmail_path *=.*$|sendmail_path = "${US_ROOTF}/core/msmtp/sendmail.bat"|' \
    -e 's|^;session.save_path = "/tmp"|session.save_path = "${US_ROOTF}/tmp"|' \
    -e 's|^;soap.wsdl_cache_dir="/tmp"|soap.wsdl_cache_dir="${US_ROOTF}/tmp"|' \
    -e 's|^;extension=gd|extension=gd|' \
    -e 's|^;extension=mbstring|extension=mbstring|' \
    -e 's|^;extension=exif|extension=exif|' \
    -e 's|^;extension=mysqli|extension=mysqli|' \
    -e 's|^;extension=openssl|extension=openssl|' \
    -e 's|^;extension=pdo_mysql|extension=pdo_mysql|' \
    -e 's|^;extension=pdo_sqlite|extension=pdo_sqlite|' \
    -e 's|^;extension=sqlite3|extension=sqlite3|' \
    -e 's|^;extension=fileinfo|extension=fileinfo|' \
    -e 's|^;extension=curl|extension=curl|' \
    -e 's|^;zend_extension=opcache$|zend_extension=${US_ROOTF}/core/'"$SHORT"'/extensions/php_opcache.dll|' \
    -e 's|^memory_limit = .*|memory_limit = 512M|' \
    -e 's|^upload_max_filesize = .*|upload_max_filesize = 256M|' \
    -e 's|^post_max_size = .*|post_max_size = 256M|' \
    -e 's|^max_execution_time = .*|max_execution_time = 120|' \
    -e 's|^max_input_time = .*|max_input_time = 120|' \
    -e 's|^;max_input_vars = 1000|max_input_vars = 5000|' \
    -e 's|^max_file_uploads = .*|max_file_uploads = 50|' \
    "$dest"
  sed -i "1s|^\[PHP\]|[PHP]\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n; PHP $VERSION $2\n; Uniform Server $3 php.ini\n; PHP Installed as Apache module\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;|" "$dest"
}

patch_ini "$PHP_ROOT/php.ini-production"  php_production.ini  Production
patch_ini "$PHP_ROOT/php.ini-production"  php_test.ini        Test
patch_ini "$PHP_ROOT/php.ini-development" php_development.ini Development

cat > "$PHP_ROOT/php-cli.ini" <<EOF
[PHP]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PHP $VERSION CLI  php-cli.ini      ;
; Uniform Server PHP CLI php-cli.ini ;
; PHP Installed as Apache module     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

extension=curl
extension=mysqli
extension=openssl
extension=gd
extension=pdo_mysql
extension=mbstring
extension=pdo_sqlite
extension=sqlite3
extension=fileinfo

extension_dir = "extensions"
error_reporting = E_ALL
memory_limit = 512M
date.timezone = "Europe/London"

sendmail_path = "\${US_ROOTF}/core/msmtp/sendmail.bat"

[COM_DOT_NET]
extension=com_dotnet
EOF

# --- Apache wiring -----------------------------------------------------------
CONF_DIR="$WORK/module/core/apache2/conf/extra_us"
mkdir -p "$CONF_DIR"
{
  for f in "$PHP_ROOT"/libsasl.dll "$PHP_ROOT"/icu*.dll; do
    [ -e "$f" ] && echo "  LoadFile \${US_ROOTF}/core/$SHORT/$(basename "$f")"
  done
  echo
  echo " # Load PHP module and add handler"
  echo "  LoadModule php_module \"\${US_ROOTF}/core/$SHORT/php8apache2_4.dll\""
  echo "  AddHandler application/x-httpd-php .php"
  echo " # Configure the path to php.ini"
  echo "  PHPIniDir \"\${US_ROOTF}/core/$SHORT/\${PHP_INI_SELECT}\""
} > "$CONF_DIR/$SHORT.conf"

# --- Package -----------------------------------------------------------------
mkdir -p "$OUT_DIR"
ZIP_NAME="UniServer-Reload_${SHORT}_module.zip"
(cd "$WORK/module" && zip -qr9 "$OLDPWD/$OUT_DIR/$ZIP_NAME" core)
echo "PHP $VERSION ($SHORT)" >> "$OUT_DIR/module-versions.txt"
echo "==> Created $OUT_DIR/$ZIP_NAME (PHP $VERSION)"
