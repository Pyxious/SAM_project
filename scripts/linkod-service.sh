#!/bin/bash
# linkod-service.sh: Start and stop LINKod services in the correct order
# Authors: LINKod Group (BSIT 4)
# Usage: sudo ./linkod-service.sh --start | --stop | --restart
# Note: Reviewed and tested by the group.

CONFIG_FILE="/etc/linkod/linkod.conf"

# Check if --help was passed
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo ./linkod-service.sh --start | --stop | --restart"
    echo "Options:"
    echo "  --start     Start mariadb, php8.5-fpm, and nginx in order"
    echo "  --stop      Stop nginx, php8.5-fpm, and mariadb in reverse order"
    echo "  --restart   Stop and start all services in order"
    echo "  --help      Show this help message"
    echo "Example:"
    echo "  sudo ./linkod-service.sh --start"
    exit 0
fi

# Require exactly 1 argument
if [ $# -ne 1 ]; then
    echo "Error: Provide one option (--start, --stop, --restart, or --help)."
    exit 2
fi

# Check that the script is run as root
USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found."
    exit 1
fi

. "$CONFIG_FILE"


# Assisted by AI: Define service order and prevents starting a second copy if it is already running
START_LIST="mariadb php8.5-fpm nginx"
STOP_LIST="nginx php8.5-fpm mariadb"

case "$1" in
    --start|start)
        # Refuse to start a second copy if all services are already running
        if systemctl is-active --quiet nginx && systemctl is-active --quiet php8.5-fpm && systemctl is-active --quiet mariadb; then
            echo "Error: $APP_NAME is already running. Refusing to start a second copy."
            exit 1
        fi

        echo "Starting $APP_NAME services in order..."
        for S in $START_LIST; do
            echo "Starting $S..."
            systemctl start "$S"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to start $S."
                exit 1
            fi
        done
        date > "$LOCK_FILE"
        echo "SUCCESS: All $APP_NAME services started ($START_LIST)."
        ;;
    --stop|stop)
        echo "Stopping $APP_NAME services in reverse order..."
        for S in $STOP_LIST; do
            echo "Stopping $S..."
            systemctl stop "$S"
        done
        rm -f "$LOCK_FILE"
        echo "SUCCESS: All $APP_NAME services stopped ($STOP_LIST)."
        ;;
    --restart|restart)
        for S in $STOP_LIST; do
            systemctl stop "$S"
        done
        for S in $START_LIST; do
            systemctl start "$S" || exit 1
        done
        date > "$LOCK_FILE"
        echo "SUCCESS: All $APP_NAME services restarted."
        ;;
    *)
        echo "Error: Invalid option $1. Use --start, --stop, --restart, or --help."
        exit 2
        ;;
esac

exit 0
