#!/usr/bin/env bash
# scripts/wake-incus.sh
# Sends a Wake-on-LAN magic packet to the Incus host.
# NOTE: As of 2026-03-01, S5 WOL is non-functional on the HP EliteDesk 800 G4 SFF
# due to a definitive hardware/BIOS limitation. This script is preserved for
# future use in case a firmware update or different hardware resolves the issue.

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
