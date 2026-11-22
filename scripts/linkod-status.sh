#!/bin/bash
# Report LINKod service state, listening ports, process CPU/RAM, and system resources.

set -u

CONFIG_FILE="/etc/linkod/linkod.conf"
REPORT_FILE=""

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") [--save FILE] [--help]

Options:
  --save FILE   Save the status output to a file
  --help        Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --save)
            [[ $# -lt 2 ]] && { echo "[ERROR] Missing filename for --save." >&2; exit 2; }
            REPORT_FILE="$2"
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

if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
else
    APP_NAME="LINKod"
    APP_DIR="/var/www/linkod"
    APP_PORT="80"
    DB_PORT="3306"
fi

PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo '8.3')"
PHP_FPM_SERVICE="php${PHP_VER}-fpm"
SERVICES=("mariadb" "${PHP_FPM_SERVICE}" "nginx")
OVERALL_OK=0

generate_report() {
    echo "=== ${APP_NAME} Status Report ($(date '+%Y-%m-%d %H:%M:%S')) ==="
    echo ""
    echo "1. SERVICE STATE"
    for svc in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "${svc}"; then
            echo "  [RUNNING] ${svc}"
        else
            echo "  [STOPPED] ${svc}"
            OVERALL_OK=1
        fi
    done

    # Check if processes are paused (state T)
    PAUSED_COUNT="$(ps -eo stat,comm | grep -E '^T.*(php-fpm|nginx)' | wc -l)"
    if [[ "${PAUSED_COUNT}" -gt 0 ]]; then
        echo "  [PAUSED]  ${PAUSED_COUNT} worker processes are suspended (state T)"
    fi

    # Check if Laravel maintenance mode is active
    if [[ -f "${APP_DIR}/storage/framework/down" ]]; then
        echo "  [MAINT]   Maintenance Mode is ON"
    else
        echo "  [LIVE]    Maintenance Mode is OFF"
    fi

    echo ""
    echo "2. LISTENING PORTS (${APP_PORT}, ${DB_PORT})"
    ss -tulpn | grep -E ":(80|3306)\b" || echo "  [WARN] No listeners on ports ${APP_PORT} or ${DB_PORT}."

    echo ""
    echo "3. PROCESS CPU & MEMORY USAGE"
    printf "  %-8s %-6s %-6s %-6s %s\n" "PID" "STAT" "%CPU" "%MEM" "COMMAND"
    ps -eo pid,stat,%cpu,%mem,comm --sort=-%mem | grep -E "(nginx|php-fpm|mariadbd|mysqld)" | awk '{printf "  %-8s %-6s %-6s %-6s %s\n", $1, $2, $3, $4, $5}'

    echo ""
    echo "4. SYSTEM RESOURCES (top, free, df)"
    top -bn1 | grep -E "^(%Cpu|top -)" | sed 's/^/  /'
    echo ""
    free -h | sed 's/^/  /'
    echo ""
    df -h / | sed 's/^/  /'
}

if [[ -n "${REPORT_FILE}" ]]; then
    mkdir -p "$(dirname "${REPORT_FILE}")"
    generate_report | tee "${REPORT_FILE}"
    chmod 640 "${REPORT_FILE}"
else
    generate_report
fi

exit "${OVERALL_OK}"
