#!/bin/bash
# linkod-maintenance.sh: Switch LINKod to "temporarily unavailable" (HTTP 503) and back
# Authors: LINKod Group (BSIT 4)
# Usage: sudo ./linkod-maintenance.sh --on | --off | --status
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONFIG_FILE="/etc/linkod/linkod.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo ./linkod-maintenance.sh --on | --off | --status"
    echo "Options:"
    echo "  --on       Enable maintenance mode (shows Temporarily Unavailable page)"
    echo "  --off      Disable maintenance mode (returns application to live)"
    echo "  --status   Show whether maintenance mode is ON or OFF"
    echo "  --help     Show this help message"
    echo "Example:"
    echo "  sudo ./linkod-maintenance.sh --on"
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Error: Provide one option (--on, --off, --status, or --help)."
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

case "$1" in
    --on|on)
        echo "Enabling maintenance mode..."
        sudo -u "$APP_USER" php "$APP_DIR/artisan" down --retry=60
        HTTP_CODE=`curl -s -o /dev/null -w "%{http_code}" "$APP_URL"`
        echo "SUCCESS: Maintenance mode is ON (HTTP $HTTP_CODE - Temporarily Unavailable)."
        ;;
    --off|off)
        echo "Disabling maintenance mode..."
        sudo -u "$APP_USER" php "$APP_DIR/artisan" up
        HTTP_CODE=`curl -s -L -o /dev/null -w "%{http_code}" "$APP_URL"`
        echo "SUCCESS: Maintenance mode is OFF (HTTP $HTTP_CODE - Live)."
        ;;
    --status|status)
        if [ -f "$APP_DIR/storage/framework/down" ]; then
            echo "STATUS: Maintenance mode is ON (HTTP 503)."
        else
            echo "STATUS: Maintenance mode is OFF (Live)."
        fi
        ;;
    *)
        echo "Error: Invalid option $1. Use --on, --off, --status, or --help."
        exit 2
        ;;
esac

exit 0
