#!/usr/bin/env bash
# scripts/suspend-incus.sh
# Sends a suspend command to the Incus host via its REST API (requires IncusOS /os prefix)

# Use the identified stable IP address
INCUS_HOST="192.168.1.129"

# Verify incus command exists
if ! command -v incus >/dev/null 2>&1; then
  echo "Error: incus CLI not found. Please install it with 'nix profile install github:nixos/nixpkgs/nixos-unstable#incus'"
  exit 1
fi

echo "Attempting to suspend Incus host at $INCUS_HOST..."

# The working endpoint discovered: /os/1.0/system/:suspend
# incus query handles certificates automatically using the local configuration.
# We expect a 'connection reset' or success depending on how fast the host sleeps.
incus query -X POST /os/1.0/system/:suspend

echo ""
echo "Suspend command sent. The host should enter sleep state shortly."
echo "Use scripts/wake-incus.sh to power it back on."
