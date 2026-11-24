#!/bin/bash
# linkod-update.sh: Back up LINKod, verify archive, apply update, and check HTTP 200
# Authors: LINKod Group (BSIT 4)
# Usage: sudo ./linkod-update.sh <UPDATE_DIR>
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONFIG_FILE="/etc/linkod/linkod.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo ./linkod-update.sh <UPDATE_DIR>"
    echo "Options:"
    echo "  --help    Show this help message"
    echo "Example:"
    echo "  sudo ./linkod-update.sh /home/justin/it123-linkod/demo-updates/broken-update"
    exit 0
fi

# Require the update directory argument
if [ $# -lt 1 ]; then
    echo "Error: Missing UPDATE_DIR argument. Run with --help for usage."
    exit 2
fi

UPDATE_DIR="$1"

# Check that the script is run as root
USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

# Check config file and verify 600 permissions
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found."
    exit 1
fi

PERM=`stat -c "%a" "$CONFIG_FILE"`
if [ "$PERM" != "600" ]; then
    echo "Error: $CONFIG_FILE must have 600 permissions."
    exit 1
fi

. "$CONFIG_FILE"

if [ ! -d "$UPDATE_DIR" ]; then
    echo "Error: Update directory $UPDATE_DIR does not exist."
    exit 1
fi

# 1. Back up database and application files
STAMP=`date +%Y%m%d-%H%M%S`
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

ARCHIVE_FILE="$BACKUP_DIR/linkod-pre-update-$STAMP.tar.gz"
SQL_FILE="$BACKUP_DIR/linkod-db-$STAMP.sql"

echo "[1/4] Backing up database and application files..."
MYSQL_PWD="$DB_PASS" mysqldump --skip-ssl -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" > "$SQL_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Database backup failed."
    exit 1
fi

tar -czf "$ARCHIVE_FILE" -C "$APP_DIR" .
if [ $? -ne 0 ]; then
    echo "Error: Archive creation failed."
    exit 1
fi
chmod 600 "$ARCHIVE_FILE" "$SQL_FILE"

# 2. Check that the backup archive is intact
echo "[2/4] Verifying backup archive ($ARCHIVE_FILE)..."
tar -tzf "$ARCHIVE_FILE" >/dev/null 2>&1 && [ -s "$SQL_FILE" ]
if [ $? -ne 0 ]; then
    echo "Error: Backup archive verification failed."
    exit 1
fi
echo "Backup verified: $ARCHIVE_FILE"

# 3. Copy update files into the application directory
echo "[3/4] Applying update from $UPDATE_DIR..."
cp -r "$UPDATE_DIR/." "$APP_DIR/"
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
sudo -u "$APP_USER" php "$APP_DIR/artisan" optimize:clear >/dev/null 2>&1

# 4. Check that the application still works (HTTP 200)
echo "[4/4] Checking if $APP_NAME still responds with HTTP 200..."
HTTP_CODE=`curl -s -L -o /dev/null -w "%{http_code}" "$APP_URL"`

if [ "$HTTP_CODE" = "200" ]; then
    echo "SUCCESS: Update applied and verified (HTTP $HTTP_CODE)."
    echo "Backup saved at: $ARCHIVE_FILE"
    exit 0
else
    echo "FAILURE: Application check failed after update (HTTP $HTTP_CODE)!"
    echo "To restore the backup by hand, run this exact command:"
    echo ""
    echo "  sudo tar -xzf $ARCHIVE_FILE -C $APP_DIR && sudo chown -R $APP_USER:$APP_GROUP $APP_DIR && sudo -u $APP_USER php $APP_DIR/artisan optimize:clear"
    echo ""
    exit 1
fi
