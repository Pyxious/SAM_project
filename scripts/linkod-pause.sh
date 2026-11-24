#!/bin/bash
# linkod-pause.sh: Suspend LINKod processes with kill -STOP and resume with kill -CONT
# Authors: LINKod Group (BSIT 4)
# Usage: sudo ./linkod-pause.sh --pause | --resume | --status
# Note: Reviewed and tested by the group.

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo ./linkod-pause.sh --pause | --resume | --status"
    echo "Options:"
    echo "  --pause    Suspend nginx and php-fpm processes with kill -STOP"
    echo "  --resume   Resume nginx and php-fpm processes with kill -CONT"
    echo "  --status   Show process state (T = paused, S = running)"
    echo "  --help     Show this help message"
    echo "Example:"
    echo "  sudo ./linkod-pause.sh --pause"
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Error: Provide one option (--pause, --resume, --status, or --help)."
    exit 2
fi

# Check that the script is run as root
USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi
# Assisted by AI: Find all running nginx and php-fpm PIDs before sending SIGSTOP/SIGCONT
PIDS=`pgrep -f "nginx|php-fpm"`
if [ "$PIDS" = "" ]; then
    echo "Error: No running nginx or php-fpm processes found."
    exit 1
fi

case "$1" in
    --pause|pause)
        echo "Suspending LINKod processes..."
        for PID in $PIDS; do
            kill -STOP $PID
        done
        echo "SUCCESS: Processes are now PAUSED (state T)."
        ps -o pid,stat,comm -p $PIDS
        ;;
    --resume|resume)
        echo "Resuming LINKod processes..."
        for PID in $PIDS; do
            kill -CONT $PID
        done
        echo "SUCCESS: Processes are now RESUMED."
        ps -o pid,stat,comm -p $PIDS
        ;;
    --status|status)
        ps -o pid,stat,comm -p $PIDS
        ;;
    *)
        echo "Error: Invalid option $1. Use --pause, --resume, --status, or --help."
        exit 2
        ;;
esac

exit 0
