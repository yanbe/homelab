#!/usr/bin/env bash
# scripts/suspend-incus.sh
# Sends a shutdown command to the Incus host securely using the incus CLI REST API.
# NOTE: This script is fully functional, but has been removed from the automatic
# desktop power sync loop because the companion wake-incus.sh (WOL) fails due to
# HP EliteDesk hardware limitations. Preserved for manual use or future hardware refresh.

echo "Attempting to shut down (poweroff) Incus host..."

# Using direct curled REST API call to bypass CLI hangs and TTY prompts.
# DISCOVERED (2026-03-03 Console):
# eno1   (1GbE Onboard): c8:d9:d2:15:6f:13 -> 192.168.1.180 (Static DHCP)
# enp1s0 (10GbE PCI-e): c4:62:37:00:8e:54 -> 192.168.1.10
# Target .180 (Onboard) as primary management link for reliable WOL/Shutdown.
if timeout 10s curl -sk -X POST --cert ~/.config/incus/client.crt --key ~/.config/incus/client.key https://192.168.1.180:8443/os/1.0/system/:poweroff > /dev/null 2>&1; then
    echo "Wait a few seconds for the host to power off."
    echo "Use scripts/wake-incus.sh to power it back on."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$SCRIPT_DIR/log-power-event.sh" "Shutdown" "Automation" "Success" "Incus shutdown command accepted."
    exit 0
else
    echo "Failed to send shutdown command to Incus host." >&2
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$SCRIPT_DIR/log-power-event.sh" "Shutdown" "Automation" "Failure" "Failed to reach Incus via REST API."
    exit 1
fi
