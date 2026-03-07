#!/usr/bin/env bash
# scripts/wake-incus.sh
# Sends a Wake-on-LAN magic packet to the Incus host.
# Onboard 1GbE interface (reliable for WOL)
MAC_ADDRESSES=(
  "c8:d9:d2:15:6f:13" # Onboard I219-LM (Verified at 192.168.1.6)
  "c4:62:37:00:8e:54" # 10GbE Port 0 (Verified at 192.168.1.10)
  "c4:62:37:00:8e:56" # Historical Port recorded
  "c4:62:37:00:8e:6d" # Registered at Router as .180
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROADCAST_IP="192.168.1.255"

# Use PowerShell to bypass WSL NAT and send directly from the Windows Host
for MAC in "${MAC_ADDRESSES[@]}"; do
    powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/wol.ps1")" "$MAC" "$BROADCAST_IP"
done

echo "Wake-on-LAN packets sent to Incus Host."
"$SCRIPT_DIR/log-power-event.sh" "WakeUp" "Automation" "Success" "WOL packets sent to Incus Host."
