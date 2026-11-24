#!/bin/bash
# linkod-install.sh: Install and configure LINKod and its services on Ubuntu
# Authors: LINKod Group (BSIT 4)
# Usage: sudo ./linkod-install.sh [/path/to/app-source]
# Note: Reviewed and tested by the group.

CONFIG_FILE="/etc/linkod/linkod.conf"
SOURCE_DIR="/home/justin/it123-linkod/app-source"

# Print help message if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo ./linkod-install.sh [SOURCE_DIR]"
    echo "Options:"
    echo "  --help    Show this help message"
    echo "Example:"
    echo "  sudo ./linkod-install.sh /home/justin/it123-linkod/app-source"
    exit 0
fi

# Optional first argument sets the source directory
if [ $# -ge 1 ]; then
    SOURCE_DIR="$1"
fi

# Check if ran by sudo/root
USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Sudo is needed to run this script."
    exit 1
fi

# Check that the application source folder exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source folder $SOURCE_DIR not found."
    exit 1
fi

# Check that the config file exists and has 600 permissions
if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p /etc/linkod
    cp /home/justin/it123-linkod/config/linkod.conf.example "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi

PERM=`stat -c "%a" "$CONFIG_FILE"`
if [ "$PERM" != "600" ]; then
    chmod 600 "$CONFIG_FILE"
fi

. "$CONFIG_FILE"

echo "=== Installing $APP_NAME ==="
# Assisted by AI: Check each required package and install only if missing (offline-safe)
echo "[1/6] Checking required packages..."
PKGS="nginx mariadb-server php-fpm php-mysql php-xml php-mbstring php-curl php-zip php-gd php-bcmath php-intl composer nodejs npm curl unzip rsync"

for P in $PKGS; do
    if ! dpkg -s "$P" >/dev/null 2>&1; then
        echo "Installing $P..."
        apt-get update -y && apt-get install -y --no-install-recommends "$P"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install $P."
            exit 1
        fi
    fi
done
echo "All required packages are installed."

# Start MariaDB and create database and user
echo "[2/6] Setting up MariaDB database ($DB_NAME)..."
systemctl start mariadb
mysql -u root -e "CREATE DATABASE IF NOT EXISTS $DB_NAME; CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'$DB_HOST'; FLUSH PRIVILEGES;"
if [ $? -ne 0 ]; then
    echo "Error: Database creation failed."
    exit 1
fi

# Copy application files and set up .env
echo "[3/6] Copying application files to $APP_DIR..."
mkdir -p "$APP_DIR" "$BACKUP_DIR" "$LOG_DIR"
rsync -a --delete --exclude='.git' --exclude='node_modules' "$SOURCE_DIR/" "$APP_DIR/"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy application files."
    exit 1
fi

cp "$APP_DIR/.env.example" "$APP_DIR/.env"
sed -i "s|^APP_URL=.*|APP_URL=$APP_URL|" "$APP_DIR/.env"
sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" "$APP_DIR/.env"
sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" "$APP_DIR/.env"
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" "$APP_DIR/.env"
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USER|" "$APP_DIR/.env"
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=\"$DB_PASS\"|" "$APP_DIR/.env"
sed -i "s|^FILESYSTEM_DISK=.*|FILESYSTEM_DISK=local|" "$APP_DIR/.env"

# Run Composer, key generation, database migrations, and seeders
echo "[4/6] Running Composer and database migrations..."
cd "$APP_DIR"
# Reuse pre-cached vendor/ if present; otherwise install Composer packages
if [ -f "$APP_DIR/vendor/autoload.php" ]; then
    COMPOSER_ALLOW_SUPERUSER=1 composer dump-autoload --optimize --no-dev --no-interaction
else
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
fi

php artisan key:generate --force && php artisan migrate --force && php artisan db:seed --force
if [ $? -ne 0 ]; then
    echo "Error: Laravel migration or seeding failed."
    exit 1
fi

# Set ownership and permissions
echo "[5/6] Setting ownership and permissions on $APP_DIR..."
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 750 {} \;
find "$APP_DIR" -type f -exec chmod 640 {} \;
chmod 750 "$APP_DIR/artisan"
chmod -R 775 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"
chmod 600 "$APP_DIR/.env"

systemctl restart php8.5-fpm && systemctl restart nginx
date > "$LOCK_FILE"

# Check that LINKod responds with HTTP 200
echo "[6/6] Verifying $APP_URL..."
HTTP_CODE=`curl -s -L -o /dev/null -w "%{http_code}" "$APP_URL"`
if [ "$HTTP_CODE" = "200" ]; then
    echo "SUCCESS: $APP_NAME is installed and responding (HTTP $HTTP_CODE)."
    exit 0
else
    echo "FAILURE: $APP_NAME returned HTTP $HTTP_CODE instead of 200."
    exit 1
fi
