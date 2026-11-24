#!/bin/bash
# linkod-status.sh: Report LINKod service state, ports, CPU/RAM, and system resources
# Authors: LINKod Group (BSIT 4)
# Usage: sudo ./linkod-status.sh [--save FILE]
# Note: Reviewed and tested by the group.

CONFIG_FILE="/etc/linkod/linkod.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo ./linkod-status.sh [--save FILE]"
    echo "Options:"
    echo "  --save FILE   Save the status report to a file"
    echo "  --help        Show this help message"
    echo "Example:"
    echo "  sudo ./linkod-status.sh --save /var/log/linkod/status.txt"
    exit 0
fi

# Check that the script is run as root
USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    APP_NAME="LINKod"
    APP_DIR="/var/www/linkod"
fi

SERVICES="mariadb php8.5-fpm nginx"
EXIT_CODE=0

NOW=`date`
echo "=== $APP_NAME Status Report ($NOW) ==="
echo ""
echo "1. SERVICE STATE"
for S in $SERVICES; do
    if systemctl is-active --quiet "$S"; then
        echo "  $S: RUNNING"
    else
        echo "  $S: STOPPED"
        EXIT_CODE=1
    fi
done
# Assisted by AI: Count paused workers (state T) and check Laravel maintenance mode file
PAUSED=`ps -eo stat,comm | grep -E "^T.*(php-fpm|nginx)" | wc -l`
if [ $PAUSED -gt 0 ]; then
    echo "  Process State: PAUSED ($PAUSED processes in state T)"
fi

# Check if maintenance mode file exists
if [ -f "$APP_DIR/storage/framework/down" ]; then
    echo "  Maintenance Mode: ON "
else
    echo "  Maintenance Mode: OFF "
fi

echo ""
echo "2. LISTENING PORTS (80 and 3306)"
ss -tulpn | grep -E ":(80|3306)\b"

echo ""
echo "3. PROCESS CPU AND MEMORY USAGE"
ps -eo pid,stat,%cpu,%mem,comm | grep -E "PID|nginx|php-fpm|mariadbd"

echo ""
echo "4. SYSTEM RESOURCES (top, free, df)"
top -bn1 | grep -E "^(top -|%Cpu)"
echo ""
free -h
echo ""
df -h /

# Save a copy to a file if --save FILE was provided
if [ "$1" = "--save" ] && [ $# -eq 2 ]; then
    "$0" > "$2"
    chmod 640 "$2"
    echo ""
    echo "Saved report to $2"
fi

exit $EXIT_CODE
