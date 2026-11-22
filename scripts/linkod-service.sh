#!/bin/bash
# Start and stop LINKod services in dependency order (MariaDB -> PHP-FPM -> Nginx).

set -u

CONFIG_FILE="/etc/linkod/linkod.conf"

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") --start | --stop | --restart | --help

Options:
  --start     Start services in order (mariadb -> php-fpm -> nginx)
  --stop      Stop services in reverse order (nginx -> php-fpm -> mariadb)
  --restart   Stop and start all services in order
  --help      Show this help message
EOF
}

if [[ $# -ne 1 ]]; then
    echo "[ERROR] Provide one option (--start, --stop, --restart, or --help)." >&2
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

PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo '8.3')"
PHP_FPM_SERVICE="php${PHP_VER}-fpm"

START_ORDER=("mariadb" "${PHP_FPM_SERVICE}" "nginx")
STOP_ORDER=("nginx" "${PHP_FPM_SERVICE}" "mariadb")

# Check if all three services are already running
is_app_running() {
    if systemctl is-active --quiet nginx && systemctl is-active --quiet "${PHP_FPM_SERVICE}" && systemctl is-active --quiet mariadb; then
        [[ -f "${LOCK_FILE}" ]] || { echo "$(date '+%Y-%m-%d %H:%M:%S')" > "${LOCK_FILE}"; chmod 640 "${LOCK_FILE}"; }
        return 0
    fi
    return 1
}

start_services() {
    # Refuse to start a second copy if already running
    if is_app_running; then
        echo "[ERROR] ${APP_NAME} is already running. Refusing to start a second copy." >&2
        exit 1
    fi

    echo "[INFO] Starting ${APP_NAME} services in order..."
    for svc in "${START_ORDER[@]}"; do
        echo "  -> Starting ${svc}..."
        systemctl start "${svc}" && systemctl is-active --quiet "${svc}" || {
            echo "[ERROR] Failed to start ${svc}." >&2
            exit 1
        }
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "${LOCK_FILE}"
    chmod 640 "${LOCK_FILE}"
    echo "[SUCCESS] Started all services (${START_ORDER[*]})."
}

stop_services() {
    echo "[INFO] Stopping ${APP_NAME} services in reverse order..."
    for svc in "${STOP_ORDER[@]}"; do
        if systemctl is-active --quiet "${svc}"; then
            echo "  -> Stopping ${svc}..."
            systemctl stop "${svc}" || { echo "[ERROR] Failed to stop ${svc}." >&2; exit 1; }
        else
            echo "  -> ${svc} is already stopped."
        fi
    done

    rm -f "${LOCK_FILE}"
    echo "[SUCCESS] Stopped all services (${STOP_ORDER[*]})."
}

case "${ACTION}" in
    --start|start)
        start_services
        ;;
    --stop|stop)
        stop_services
        ;;
    --restart|restart)
        stop_services
        start_services
        ;;
    *)
        echo "[ERROR] Invalid option: ${ACTION}" >&2
        exit 2
        ;;
esac

exit 0
