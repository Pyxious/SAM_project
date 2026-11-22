#!/bin/bash
# Back up LINKod and database, verify backup archive, apply update, and check HTTP 200.

set -u

CONFIG_FILE="/etc/linkod/linkod.conf"

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") <UPDATE_DIR> | --help

Arguments:
  UPDATE_DIR   Directory containing updated files to apply
EOF
}

if [[ $# -lt 1 ]]; then
    echo "[ERROR] Missing UPDATE_DIR argument." >&2
    exit 2
fi

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

UPDATE_DIR="$1"

# Check for root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Run this script with sudo." >&2
    exit 1
fi

# Verify config file exists and has 600 permissions
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "[ERROR] Config file ${CONFIG_FILE} not found." >&2
    exit 1
fi

if [[ "$(stat -c "%a" "${CONFIG_FILE}")" != "600" ]]; then
    echo "[ERROR] ${CONFIG_FILE} must have 600 permissions." >&2
    exit 1
fi

source "${CONFIG_FILE}"

if [[ ! -d "${UPDATE_DIR}" ]]; then
    echo "[ERROR] Update directory not found: ${UPDATE_DIR}" >&2
    exit 1
fi

# 1. Back up database and application files
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

ARCHIVE_FILE="${BACKUP_DIR}/linkod-pre-update-${TIMESTAMP}.tar.gz"
SQL_DUMP_FILE="${BACKUP_DIR}/linkod-db-${TIMESTAMP}.sql"

echo "[1/4] Backing up database and application files..."
MYSQL_PWD="${DB_PASS}" mysqldump --skip-ssl -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" "${DB_NAME}" > "${SQL_DUMP_FILE}" || {
    echo "[ERROR] Database backup failed." >&2
    exit 1
}
chmod 600 "${SQL_DUMP_FILE}"

tar -czf "${ARCHIVE_FILE}" -C "${APP_DIR}" . || {
    echo "[ERROR] Archive creation failed." >&2
    exit 1
}
chmod 600 "${ARCHIVE_FILE}"

# 2. Verify that the archive is intact
echo "[2/4] Verifying backup archive (${ARCHIVE_FILE})..."
tar -tzf "${ARCHIVE_FILE}" >/dev/null 2>&1 && [[ -s "${SQL_DUMP_FILE}" ]] || {
    echo "[ERROR] Backup verification failed. Aborting update." >&2
    exit 1
}
echo "  -> Verified backup: ${ARCHIVE_FILE}"

# 3. Copy update files into application directory
echo "[3/4] Applying update from ${UPDATE_DIR}..."
cp -r "${UPDATE_DIR}/." "${APP_DIR}/" || {
    echo "[ERROR] Failed to copy update files." >&2
    exit 1
}

chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
cd "${APP_DIR}" && sudo -u "${APP_USER}" php artisan optimize:clear >/dev/null 2>&1 || true

# 4. Check if the application still responds with HTTP 200
echo "[4/4] Verifying application health..."
HTTP_CODE="$(curl -s -L -o /dev/null -w "%{http_code}" "${APP_URL}")"

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo "[SUCCESS] Update applied and verified (HTTP ${HTTP_CODE})."
    echo "Backup saved at: ${ARCHIVE_FILE}"
    exit 0
else
    echo "[FAILURE] Post-update check failed (HTTP ${HTTP_CODE})!" >&2
    echo "To restore the backup manually, run:" >&2
    echo "" >&2
    echo "  sudo tar -xzf ${ARCHIVE_FILE} -C ${APP_DIR} && sudo chown -R ${APP_USER}:${APP_GROUP} ${APP_DIR} && sudo -u ${APP_USER} php ${APP_DIR}/artisan optimize:clear" >&2
    echo "" >&2
    exit 1
fi
