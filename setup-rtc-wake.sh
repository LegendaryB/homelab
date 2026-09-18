#!/usr/bin/env bash
#
# setup-rtc-wake.sh — Configure automated daily RTC wake-up on a Linux system
#
# What it does:
#   1. Verifies kernel sysfs RTC support (/sys/class/rtc/rtc0/wakealarm)
#   2. Prompts the user for a daily wake time (or takes $1 / default)
#   3. Cleans up any legacy rtc-wake.service to prevent race conditions
#   4. Ensures the systemd shutdown directory exists and installs the hook
#      (executes after hwclock/timesyncd, preventing alarm resets during poweroff)
#   5. Arms the alarm immediately for the next cycle
#   6. Reads and displays the active hardware RTC alarm status
#
# Usage:
#   sudo ./setup-rtc-wake.sh            # interactive prompt (with default)
#   sudo ./setup-rtc-wake.sh 19:30:00   # non-interactive via argument
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo ./setup-rtc-wake.sh)" >&2
    exit 1
fi

# --- 1. Check RTC hardware support ------------------------------------------
SYSFS_RTC="/sys/class/rtc/rtc0/wakealarm"
PROC_RTC="/proc/driver/rtc"

if [[ ! -w "$SYSFS_RTC" ]]; then
    echo "ERROR: $SYSFS_RTC not found or not writable." >&2
    echo "Your kernel or motherboard may lack programmable RTC alarm support." >&2
    exit 1
fi

# --- 2. Query target wake time from user ------------------------------------
DEFAULT_TIME="19:30:00"
INPUT_TIME="${1:-}"

if [[ -z "$INPUT_TIME" ]]; then
    read -rp "Enter daily wake time [HH:MM:SS] (default: ${DEFAULT_TIME}): " USER_INPUT
    WAKE_TIME="${USER_INPUT:-$DEFAULT_TIME}"
else
    WAKE_TIME="$INPUT_TIME"
fi

# Validate format using date
if ! date -d "$WAKE_TIME" >/dev/null 2>&1; then
    echo "ERROR: Invalid time format '$WAKE_TIME'. Use HH:MM or HH:MM:SS (e.g. 19:30:00)." >&2
    exit 1
fi

# Standardize format to HH:MM:SS
WAKE_TIME=$(date -d "$WAKE_TIME" +%H:%M:%S)
echo "Target wake time set to: $WAKE_TIME (local time)"

# --- 3. Clean up legacy systemd service if present --------------------------
OLD_SERVICE="/etc/systemd/system/rtc-wake.service"
if [[ -f "$OLD_SERVICE" ]]; then
    echo "Removing legacy systemd service to prevent conflicts..."
    systemctl disable --now rtc-wake.service >/dev/null 2>&1 || true
    rm -f "$OLD_SERVICE"
    systemctl daemon-reload
fi

# --- 4. Install final systemd system-shutdown hook --------------------------
HOOK_DIR="/usr/lib/systemd/system-shutdown"
HOOK_PATH="${HOOK_DIR}/rtc-wake"

echo "Ensuring directory exists: ${HOOK_DIR}..."
mkdir -p "${HOOK_DIR}"

echo "Installing system-shutdown hook at $HOOK_PATH..."

cat > "$HOOK_PATH" <<EOF
#!/bin/sh
# Systemd passes 'poweroff', 'reboot', or 'halt' as \$1
if [ "\$1" = "poweroff" ] || [ "\$1" = "halt" ]; then
    TARGET=\$(date -d "$WAKE_TIME" +%s)
    NOW=\$(date +%s)

    # If target time is past or less than 120 seconds ahead, schedule for tomorrow
    if [ \$((TARGET - NOW)) -le 120 ]; then
        TARGET=\$(date -d "tomorrow $WAKE_TIME" +%s)
    fi

    echo 0 > $SYSFS_RTC
    sleep 0.5
    echo "\$TARGET" > $SYSFS_RTC
fi
EOF

chmod +x "$HOOK_PATH"
chown root:root "$HOOK_PATH"

# Also ensure /lib compatibility link/path if system differs
if [[ -d /lib/systemd && ! -d /lib/systemd/system-shutdown && ! -L /lib ]]; then
    mkdir -p /lib/systemd/system-shutdown
fi

# --- 5. Arm alarm immediately for testing -----------------------------------
echo "Arming RTC alarm immediately for testing..."
TARGET=$(date -d "$WAKE_TIME" +%s)
NOW=$(date +%s)
if [ $((TARGET - NOW)) -le 120 ]; then
    TARGET=$(date -d "tomorrow $WAKE_TIME" +%s)
fi

echo 0 > "$SYSFS_RTC"
sleep 0.5
echo "$TARGET" > "$SYSFS_RTC"

# --- 6. Print summary -------------------------------------------------------
ALRM_TIME=$(grep -E "^alrm_time" "$PROC_RTC" 2>/dev/null | awk '{print $3}' || echo "unknown")
ALRM_DATE=$(grep -E "^alrm_date" "$PROC_RTC" 2>/dev/null | awk '{print $3}' || echo "unknown")
ALRM_IRQ=$(grep -E "^alarm_IRQ" "$PROC_RTC" 2>/dev/null | awk '{print $3}' || echo "unknown")

echo ""
echo "==================================================================="
echo " RTC Wake Hook setup complete"
echo "==================================================================="
echo " Target time (Local): $WAKE_TIME"
echo " Programmed UTC date: $ALRM_DATE"
echo " Programmed UTC time: $ALRM_TIME"
echo " Hardware interrupt:  $ALRM_IRQ"
echo ""
echo " How it works now:"
echo "  - Installed to $HOOK_PATH"
echo "  - Fires at the absolute end of shutdown AFTER systemd-timesyncd"
echo "    and hwclock finish, preventing the RTC alarm from being wiped."
echo "  - Only triggers on real poweroffs, not during reboots."
echo "==================================================================="
