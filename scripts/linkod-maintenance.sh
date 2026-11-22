#!/bin/bash
# Switch LINKod between Maintenance Mode (HTTP 503) and Live Mode (HTTP 200).

set -u

CONFIG_FILE="/etc/linkod/linkod.conf"

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") --on | --off | --status | --help

Options:
  --on       Enable maintenance mode (returns HTTP 503 Temporarily Unavailable)
  --off      Disable maintenance mode (returns to live HTTP 200)
  --status   Show whether maintenance mode is currently active
  --help     Show this help message
EOF
}

if [[ $# -ne 1 ]]; then
    echo "[ERROR] Provide one option (--on, --off, --status, or --help)." >&2
    exit 2
fi

ACTION="$1"
if [[ "${ACTION}" == "--help" ]] || [[ "${ACTION}" == "-h" ]]; then
    show_help
    exit 0
fi

# Check for root privileges
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Run this script with sudo." >&2
    exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "[ERROR] Config file ${CONFIG_FILE} not found." >&2
    exit 1
fi

source "${CONFIG_FILE}"

# Create 503 maintenance view if it does not exist yet
ERRORS_DIR="${APP_DIR}/resources/views/errors"
MAINT_VIEW="${ERRORS_DIR}/503.blade.php"
if [[ ! -f "${MAINT_VIEW}" ]]; then
    mkdir -p "${ERRORS_DIR}"
    cat >"${MAINT_VIEW}" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>LINKod - Temporarily Unavailable</title>
    <style>
        body { font-family: sans-serif; background: #f8fafc; color: #0f172a; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .card { background: #fff; padding: 2rem; border-radius: 0.5rem; box-shadow: 0 2px 10px rgba(0,0,0,0.08); max-width: 450px; text-align: center; border-top: 4px solid #2563eb; }
    </style>
</head>
<body>
    <div class="card">
        <h1>LINKod is Temporarily Unavailable</h1>
        <p>We are currently performing scheduled maintenance. Please check back shortly.</p>
    </div>
</body>
</html>
HTML
    chown -R "${APP_USER}:${APP_GROUP}" "${ERRORS_DIR}"
    chmod 640 "${MAINT_VIEW}"
fi

case "${ACTION}" in
    --on|on)
        echo "[INFO] Enabling maintenance mode..."
        cd "${APP_DIR}" && sudo -u "${APP_USER}" php artisan down --retry=60 || exit 1
        HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}")"
        echo "[SUCCESS] Maintenance mode ON (HTTP ${HTTP_CODE} - Temporarily Unavailable)."
        ;;
    --off|off)
        echo "[INFO] Disabling maintenance mode..."
        cd "${APP_DIR}" && sudo -u "${APP_USER}" php artisan up || exit 1
        HTTP_CODE="$(curl -s -L -o /dev/null -w "%{http_code}" "${APP_URL}")"
        echo "[SUCCESS] Maintenance mode OFF (HTTP ${HTTP_CODE} - Live)."
        ;;
    --status|status)
        if [[ -f "${APP_DIR}/storage/framework/down" ]]; then
            echo "[STATUS] Maintenance mode is ON (HTTP 503)."
        else
            echo "[STATUS] Maintenance mode is OFF (Live)."
        fi
        ;;
    *)
        echo "[ERROR] Invalid option: ${ACTION}" >&2
        exit 2
        ;;
esac

exit 0
