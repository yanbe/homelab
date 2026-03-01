#!/usr/bin/env bash
# scripts/wake-incus.sh
# Sends a Wake-on-LAN magic packet to the Incus host.
# NOTE: As of 2026-03-01, S5 WOL is non-functional on the HP EliteDesk 800 G4 SFF
# due to a definitive hardware/BIOS limitation. This script is preserved for
# future use in case a firmware update or different hardware resolves the issue.

# Onboard 1GbE interface (reliable for WOL)
MAC_ADDRESSES=(
  "c4:62:37:00:8e:56"
  "c4:62:37:00:8e:54"
  "00:2b:f5:71:72:0d"
  # 10GbE NIC (Intel X540-AT2) - Does not support Wake-on-LAN (Magic Packet) by design.
  # "a0:36:9f:5c:ec:cc"
  # "a0:36:9f:5c:ec:ce"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROADCAST_IP="192.168.1.255"

# Use PowerShell to bypass WSL NAT and send directly from the Windows Host
for MAC in "${MAC_ADDRESSES[@]}"; do
    powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/wol.ps1")" "$MAC" "$BROADCAST_IP"
done

echo "Wake-on-LAN packets sent to Incus Host."
