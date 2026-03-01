#!/usr/bin/env bash
# scripts/suspend-incus.sh
# Sends a shutdown command to the Incus host securely using the incus CLI REST API.
# NOTE: This script is fully functional, but has been removed from the automatic
# desktop power sync loop because the companion wake-incus.sh (WOL) fails due to
# HP EliteDesk hardware limitations. Preserved for manual use or future hardware refresh.

echo "Attempting to shut down (poweroff) Incus host..."

# Using direct curled REST API call to bypass CLI hangs and TTY prompts.
# We target 192.168.1.138 (onboard NIC) which is more stable than the 10GbE IP.
timeout 10s curl -sk -X POST --cert ~/.config/incus/client.crt --key ~/.config/incus/client.key https://192.168.1.138:8443/os/1.0/system/:poweroff > /dev/null 2>&1

echo "Wait a few seconds for the host to power off."
echo "Use scripts/wake-incus.sh to power it back on."

