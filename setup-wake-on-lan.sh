#!/usr/bin/env bash
#
# setup-wol.sh — Enable and persist Wake-on-LAN on a Debian-based system
#
# What it does:
#   1. Installs ethtool if missing
#   2. Detects (or accepts) the network interface
#   3. Checks the NIC supports magic-packet WoL
#   4. Enables WoL now
#   5. Installs a systemd service so it survives reboots/driver reloads
#   6. Prints the MAC address you'll need for sending magic packets
#
# Usage:
#   sudo ./setup-wol.sh            # auto-detect interface
#   sudo ./setup-wol.sh eth0       # specify interface explicitly
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo ./setup-wol.sh)" >&2
    exit 1
fi

# --- 1. Ensure ethtool is installed -----------------------------------------
if ! command -v ethtool >/dev/null 2>&1; then
    echo "Installing ethtool..."
    apt update -qq && apt install -y ethtool
fi

# --- 2. Determine interface --------------------------------------------------
IFACE="${1:-}"
if [[ -z "$IFACE" ]]; then
    # Pick the first interface that has a default route (best guess at the "main" NIC)
    IFACE=$(ip route show default | awk '/default/ {print $5; exit}')
    if [[ -z "$IFACE" ]]; then
        echo "Could not auto-detect a network interface. Run again with:" >&2
        echo "  sudo ./setup-wol.sh <interface-name>" >&2
        echo "(see 'ip link show' for a list of interfaces)" >&2
        exit 1
    fi
    echo "Auto-detected interface: $IFACE"
fi

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "Interface '$IFACE' not found. Available interfaces:" >&2
    ip -brief link show >&2
    exit 1
fi

# --- 3. Check WoL support -----------------------------------------------------
echo "Checking Wake-on-LAN support on $IFACE..."
SUPPORT_LINE=$(ethtool "$IFACE" 2>/dev/null | grep "Supports Wake-on" || true)
echo "  $SUPPORT_LINE"

if [[ "$SUPPORT_LINE" != *g* ]]; then
    echo "WARNING: This NIC does not appear to advertise magic-packet (g) support." >&2
    echo "WoL may still be blockable/enablable via BIOS/UEFI, but the OS side may not work." >&2
fi

# --- 4. Enable WoL now ---------------------------------------------------------
echo "Enabling magic-packet Wake-on-LAN on $IFACE..."
ethtool -s "$IFACE" wol g

CURRENT=$(ethtool "$IFACE" 2>/dev/null | grep "Wake-on:" || true)
echo "  $CURRENT"

# --- 5. Install systemd service so it persists across reboots -----------------
SERVICE_PATH="/etc/systemd/system/wol.service"
echo "Installing systemd service at $SERVICE_PATH..."

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Enable Wake-on-LAN on $IFACE
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s $IFACE wol g

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wol.service

# --- 6. Print summary -----------------------------------------------------------
MAC=$(cat /sys/class/net/"$IFACE"/address)

echo ""
echo "==================================================================="
echo " Wake-on-LAN setup complete"
echo "==================================================================="
echo " Interface:   $IFACE"
echo " MAC address: $MAC"
echo ""
echo " Next steps:"
echo "  1. Enable WoL in your BIOS/UEFI (often 'Wake on LAN' or"
echo "     'Power On by PCI-E/PCIe'). The OS-side setting above is not"
echo "     enough on its own."
echo "  2. Reboot and re-run 'ethtool $IFACE | grep Wake-on' to confirm"
echo "     it still shows 'Wake-on: g' after the reboot."
echo "  3. Test from another machine on the network:"
echo "       sudo apt install wakeonlan"
echo "       wakeonlan $MAC"
echo "     (shut this machine down first, then send the packet)"
echo "==================================================================="
