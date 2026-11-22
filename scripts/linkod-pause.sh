#!/bin/bash
# Suspend LINKod processes with kill -STOP and resume them with kill -CONT.

set -u

CONFIG_FILE="/etc/linkod/linkod.conf"

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") --pause | --resume | --status | --help

Options:
  --pause    Freeze LINKod processes with kill -STOP
  --resume   Resume LINKod processes with kill -CONT
  --status   Show current process state (T = paused, S/R = running)
  --help     Show this help message
EOF
}

if [[ $# -ne 1 ]]; then
    echo "[ERROR] Provide one option (--pause, --resume, --status, or --help)." >&2
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

[[ -f "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}" || APP_NAME="LINKod"

# Get running nginx and php-fpm PIDs
mapfile -t APP_PIDS < <(pgrep -f "(nginx|php-fpm)" || true)

if [[ "${#APP_PIDS[@]}" -eq 0 ]]; then
    echo "[ERROR] No running ${APP_NAME} processes found." >&2
    exit 1
fi

case "${ACTION}" in
    --pause|pause)
        echo "[INFO] Suspending ${APP_NAME} processes with kill -STOP..."
        for pid in "${APP_PIDS[@]}"; do
            kill -STOP "${pid}" || exit 1
        done
        echo "[SUCCESS] Processes are PAUSED (state T)."
        ps -o pid,stat,comm -p "${APP_PIDS[@]}"
        ;;
    --resume|resume)
        echo "[INFO] Resuming ${APP_NAME} processes with kill -CONT..."
        for pid in "${APP_PIDS[@]}"; do
            kill -CONT "${pid}" || exit 1
        done
        echo "[SUCCESS] Processes are RESUMED."
        ps -o pid,stat,comm -p "${APP_PIDS[@]}"
        ;;
    --status|status)
        ps -o pid,stat,comm -p "${APP_PIDS[@]}"
        ;;
    *)
        echo "[ERROR] Invalid option: ${ACTION}" >&2
        exit 2
        ;;
esac

exit 0
