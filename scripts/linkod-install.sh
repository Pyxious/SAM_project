#!/bin/bash
# Install and configure LINKod and its required services on Ubuntu.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/app-source"
CONFIG_FILE="/etc/linkod/linkod.conf"
CONFIG_TEMPLATE="$(cd "${SCRIPT_DIR}/.." && pwd)/config/linkod.conf.example"

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") [--source DIR] [--config FILE] [--help]

Options:
  --source DIR    Path to the application source directory
  --config FILE   Path to configuration file (default: /etc/linkod/linkod.conf)
  --help          Show this help message
EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --source)
            [[ $# -lt 2 ]] && { echo "[ERROR] Missing argument for --source." >&2; exit 2; }
            SOURCE_DIR="$2"
            shift 2
            ;;
        --config)
            [[ $# -lt 2 ]] && { echo "[ERROR] Missing argument for --config." >&2; exit 2; }
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# Check for root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Run this script with sudo." >&2
    exit 1
fi

# Check that the Laravel source directory exists
if [[ ! -d "${SOURCE_DIR}" ]] || [[ ! -f "${SOURCE_DIR}/artisan" ]]; then
    echo "[ERROR] Source directory not found: ${SOURCE_DIR}" >&2
    exit 1
fi

# Create config file if missing and enforce 600 permissions
if [[ ! -f "${CONFIG_FILE}" ]]; then
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    cp "${CONFIG_TEMPLATE}" "${CONFIG_FILE}" || { echo "[ERROR] Missing config template." >&2; exit 1; }
    chown root:root "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
fi

if [[ "$(stat -c "%a" "${CONFIG_FILE}")" != "600" ]]; then
    chmod 600 "${CONFIG_FILE}"
fi

source "${CONFIG_FILE}"

echo "=== Installing ${APP_NAME} on $(hostname) ==="

# 1. Install required packages if any are missing
echo "[1/6] Checking required packages..."
export DEBIAN_FRONTEND=noninteractive
REQUIRED_PKGS=(nginx mariadb-server php-fpm php-mysql php-xml php-mbstring php-curl php-zip php-gd php-bcmath php-intl composer nodejs npm curl unzip rsync)

MISSING_PKGS=0
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
        MISSING_PKGS=1
        break
    fi
done

if [[ "${MISSING_PKGS}" -eq 1 ]]; then
    apt-get update -y || { echo "[ERROR] apt-get update failed." >&2; exit 1; }
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
            echo "  -> Installing ${pkg}..."
            apt-get install -y --no-install-recommends "${pkg}" || { echo "[ERROR] Failed to install ${pkg}." >&2; exit 1; }
        fi
    done
else
    echo "  -> All packages already installed."
fi

PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_FPM_SERVICE="php${PHP_VER}-fpm"
PHP_FPM_SOCK="/run/php/php${PHP_VER}-fpm.sock"

# 2. Configure MariaDB database and user
echo "[2/6] Setting up MariaDB database (${DB_NAME})..."
systemctl enable mariadb >/dev/null 2>&1 || true
systemctl start mariadb || { echo "[ERROR] Could not start MariaDB." >&2; exit 1; }

mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL
if [[ $? -ne 0 ]]; then
    echo "[ERROR] Database setup failed." >&2
    exit 1
fi

# 3. Copy application files and configure .env
echo "[3/6] Copying files to ${APP_DIR}..."
mkdir -p "${APP_DIR}" "${BACKUP_DIR}" "${LOG_DIR}"
rsync -a --delete --exclude='.git' --exclude='node_modules' "${SOURCE_DIR}/" "${APP_DIR}/" || {
    echo "[ERROR] Failed to copy application files." >&2
    exit 1
}

cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
sed -i -E "s|^APP_ENV=.*|APP_ENV=production|" "${APP_DIR}/.env"
sed -i -E "s|^APP_DEBUG=.*|APP_DEBUG=false|" "${APP_DIR}/.env"
sed -i -E "s|^APP_URL=.*|APP_URL=${APP_URL}|" "${APP_DIR}/.env"
sed -i -E "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" "${APP_DIR}/.env"
sed -i -E "s|^DB_HOST=.*|DB_HOST=${DB_HOST}|" "${APP_DIR}/.env"
sed -i -E "s|^DB_PORT=.*|DB_PORT=${DB_PORT}|" "${APP_DIR}/.env"
sed -i -E "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" "${APP_DIR}/.env"
sed -i -E "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" "${APP_DIR}/.env"
sed -i -E "s|^DB_PASSWORD=.*|DB_PASSWORD=\"${DB_PASS}\"|" "${APP_DIR}/.env"
sed -i -E "s|^FILESYSTEM_DISK=.*|FILESYSTEM_DISK=local|" "${APP_DIR}/.env"

# 4. Install dependencies and run migrations
echo "[4/6] Configuring dependencies and database migrations..."
cd "${APP_DIR}" || exit 1
if [[ -f "${APP_DIR}/vendor/autoload.php" ]]; then
    COMPOSER_ALLOW_SUPERUSER=1 composer dump-autoload --optimize --no-dev --no-interaction || exit 1
else
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction || exit 1
fi

php artisan key:generate --force && php artisan migrate --force && php artisan db:seed --force || {
    echo "[ERROR] Artisan setup failed." >&2
    exit 1
}

if [[ ! -f "${APP_DIR}/public/build/manifest.json" ]] && [[ -f "${APP_DIR}/package.json" ]]; then
    npm install --ignore-scripts && npm run build || { echo "[ERROR] Asset build failed." >&2; exit 1; }
fi

# 5. Set ownership and permissions
echo "[5/6] Setting file ownership and permissions..."
chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
find "${APP_DIR}" -type d -exec chmod 750 {} \;
find "${APP_DIR}" -type f -exec chmod 640 {} \;
chmod 750 "${APP_DIR}/artisan"
chmod -R 775 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
chmod 600 "${APP_DIR}/.env"

# Configure Nginx site
cat >/etc/nginx/sites-available/linkod <<NGINX
server {
    listen ${APP_PORT};
    server_name _;
    root ${APP_DIR}/public;

    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:${PHP_FPM_SOCK};
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/linkod /etc/nginx/sites-enabled/linkod
rm -f /etc/nginx/sites-enabled/default

systemctl enable "${PHP_FPM_SERVICE}" nginx >/dev/null 2>&1 || true
systemctl restart "${PHP_FPM_SERVICE}" && systemctl restart nginx || {
    echo "[ERROR] Failed to start PHP-FPM or Nginx." >&2
    exit 1
}
echo "$(date '+%Y-%m-%d %H:%M:%S')" > "${LOCK_FILE}"

# 6. Verify HTTP 200 response
echo "[6/6] Checking HTTP response at ${APP_URL}..."
HTTP_CODE="$(curl -s -L -o /dev/null -w "%{http_code}" "${APP_URL}")"
if [[ "${HTTP_CODE}" == "200" ]]; then
    echo "[SUCCESS] ${APP_NAME} is running (HTTP ${HTTP_CODE}) at ${APP_URL}."
    exit 0
else
    echo "[FAILURE] HTTP check returned ${HTTP_CODE} instead of 200." >&2
    exit 1
fi
