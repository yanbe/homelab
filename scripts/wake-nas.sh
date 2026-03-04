#!/usr/bin/env bash
# scripts/wake-nas.sh
# Sends a Wake-on-LAN (WOL) magic packet to the NAS onboard 1GbE interface.

# Onboard 1GbE interface (reliable for WOL)
NAS_MAC="fc:15:b4:90:35:7c"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROADCAST_IP="192.168.1.255"

# Use PowerShell to bypass WSL NAT and send directly from the Windows Host
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/wol.ps1")" "$NAS_MAC" "$BROADCAST_IP"

echo "Wake-on-LAN packet sent to NAS ($NAS_MAC)."
"$SCRIPT_DIR/log-power-event.sh" "WakeUp" "Automation" "Success" "WOL packet sent to MAC $NAS_MAC"
