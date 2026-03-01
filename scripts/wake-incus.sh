#!/usr/bin/env bash
# scripts/wake-incus.sh
# Send a Wake-on-LAN (WOL) magic packet to the Incus host (HP EliteDesk).

# Extracted MAC addresses for the Incus host physical interfaces
MAC_ADDRESSES=(
  "c4:62:37:00:8e:54"
  "c8:d9:d2:15:6f:13"
)

# Use Nix shell to provide wakeonlan if the command does not exist natively
if ! command -v wakeonlan >/dev/null 2>&1; then
    echo "wakeonlan not found. Running via nixpkgs..."
    for MAC in "${MAC_ADDRESSES[@]}"; do
        nix run nixpkgs#wakeonlan -- "$MAC"
    done
else
    for MAC in "${MAC_ADDRESSES[@]}"; do
        wakeonlan "$MAC"
    done
fi

echo "Wake-on-LAN packets sent to Incus Host."
