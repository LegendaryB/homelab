#!/usr/bin/env bash
#
# setup-autoshutdown.sh — Configure automated daily shutdown via systemd timer
#
# What it does:
#   1. Accepts (or defaults to) a daily shutdown time (HH:MM:SS)
#   2. Installs a systemd service that triggers systemctl poweroff
#   3. Installs a systemd calendar timer to trigger the service daily
#   4. Enables and activates the timer immediately
#   5. Shows the next scheduled shutdown trigger
#
# Usage:
#   sudo ./setup-autoshutdown.sh            # default target: 23:30:00
#   sudo ./setup-autoshutdown.sh 01:00:00   # custom target time
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo ./setup-autoshutdown.sh)" >&2
    exit 1
fi

# --- 1. Determine target shutdown time --------------------------------------
SHUTDOWN_TIME="${1:-23:30:00}"

# Validate HH:MM or HH:MM:SS format
if ! date -d "$SHUTDOWN_TIME" >/dev/null 2>&1; then
    echo "ERROR: Invalid time format '$SHUTDOWN_TIME'. Use HH:MM or HH:MM:SS (e.g. 23:30:00)." >&2
    exit 1
fi

echo "Target shutdown time set to: $SHUTDOWN_TIME (local time)"

# --- 2. Install systemd service ---------------------------------------------
SERVICE_PATH="/etc/systemd/system/autoshutdown.service"
echo "Installing systemd service at $SERVICE_PATH..."

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Automated System Shutdown
Documentation=man:systemd.special(7)

[Service]
Type=oneshot
ExecStart=/bin/systemctl poweroff
EOF

# --- 3. Install systemd timer -----------------------------------------------
TIMER_PATH="/etc/systemd/system/autoshutdown.timer"
echo "Installing systemd timer at $TIMER_PATH..."

cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Daily Automated Shutdown Timer
Documentation=man:systemd.timer(5)

[Timer]
OnCalendar=*-*-* $SHUTDOWN_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- 4. Reload and enable timer ---------------------------------------------
echo "Reloading systemd daemon and enabling autoshutdown.timer..."
systemctl daemon-reload
systemctl enable --now autoshutdown.timer

# --- 5. Print summary -------------------------------------------------------
NEXT_TRIGGER=$(systemctl list-timers autoshutdown.timer --no-legend 2>/dev/null | awk '{print $1, $2, $3, $4}' || echo "unknown")

echo ""
echo "==================================================================="
echo " Auto-Shutdown setup complete"
echo "==================================================================="
echo " Target time (Local): $SHUTDOWN_TIME"
echo " Next trigger:        $NEXT_TRIGGER"
echo ""
echo " Management commands:"
echo "  - Check schedule:  systemctl list-timers autoshutdown.timer"
echo "  - Disable:         sudo systemctl disable --now autoshutdown.timer"
echo "  - Enable:          sudo systemctl enable --now autoshutdown.timer"
echo ""
echo " Flow overview:"
echo "  When this timer fires, systemctl poweroff is invoked."
echo "  During shutdown, your rtc-wake.service will automatically hook in"
echo "  and program the hardware alarm for the next wake-up cycle."
echo "==================================================================="
