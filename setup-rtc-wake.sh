#!/usr/bin/env bash
#
# setup-rtc-wake.sh — Configure automated daily RTC wake-up on a Linux system
#
# What it does:
#   1. Verifies kernel sysfs RTC support (/sys/class/rtc/rtc0/wakealarm)
#   2. Accepts (or defaults to) a target wake time (HH:MM:SS)
#   3. Installs an inline systemd shutdown hook (no auxiliary scripts)
#   4. Enables and arms the service immediately
#   5. Reads and displays the active hardware RTC alarm status
#
# Usage:
#   sudo ./setup-rtc-wake.sh            # default target: 19:30:00
#   sudo ./setup-rtc-wake.sh 07:00:00   # custom target time
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

# --- 2. Determine target wake time ------------------------------------------
WAKE_TIME="${1:-19:30:00}"

# Validate HH:MM or HH:MM:SS format
if ! date -d "$WAKE_TIME" >/dev/null 2>&1; then
    echo "ERROR: Invalid time format '$WAKE_TIME'. Use HH:MM or HH:MM:SS (e.g. 19:30:00)." >&2
    exit 1
fi

echo "Target wake time set to: $WAKE_TIME (local time)"

# --- 3. Install systemd service ---------------------------------------------
SERVICE_PATH="/etc/systemd/system/rtc-wake.service"
echo "Installing systemd service at $SERVICE_PATH..."

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Set RTC wake alarm for next $WAKE_TIME
DefaultDependencies=no
Before=shutdown.target poweroff.target halt.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 0 > $SYSFS_RTC && date -d "\$([ \$(date +%%s) -ge \$(date -d $WAKE_TIME +%%s) ] && echo tomorrow) $WAKE_TIME" +%%s > $SYSFS_RTC'

[Install]
WantedBy=shutdown.target poweroff.target halt.target
EOF

# --- 4. Reload and enable service -------------------------------------------
echo "Reloading systemd daemon and enabling rtc-wake.service..."
systemctl daemon-reload
systemctl enable rtc-wake.service

# Arm the alarm immediately for testing
echo "Triggering test write to $SYSFS_RTC..."
systemctl start rtc-wake.service

# --- 5. Print summary -------------------------------------------------------
ALRM_TIME=$(grep -E "^alrm_time" "$PROC_RTC" 2>/dev/null | awk '{print $3}' || echo "unknown")
ALRM_DATE=$(grep -E "^alrm_date" "$PROC_RTC" 2>/dev/null | awk '{print $3}' || echo "unknown")
ALRM_IRQ=$(grep -E "^alarm_IRQ" "$PROC_RTC" 2>/dev/null | awk '{print $3}' || echo "unknown")

echo ""
echo "==================================================================="
echo " RTC Wake setup complete"
echo "==================================================================="
echo " Target time (Local): $WAKE_TIME"
echo " Programmed UTC date: $ALRM_DATE"
echo " Programmed UTC time: $ALRM_TIME"
echo " Hardware interrupt:  $ALRM_IRQ"
echo ""
echo " Next steps:"
echo "  1. Ensure 'Deep Sleep' is disabled in your BIOS/UEFI so the board"
echo "     maintains standby power."
echo "  2. Ensure RTC alarm is set to 'By OS' in BIOS/UEFI (if available)."
echo "  3. When shutting down (sudo poweroff), systemd will automatically"
echo "     program the hardware alarm to wake the machine at $WAKE_TIME."
echo "==================================================================="
