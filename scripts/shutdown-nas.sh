#!/usr/bin/env bash
# scripts/suspend-nas.sh
# Sends a suspend command to the NAS via SSH using the automation key.

TARGET_HOST="root@nas.local"
KEY_PATH="$HOME/.ssh/id_nas_automation"

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Automation key not found: $KEY_PATH" >&2
  exit 1
fi

echo "Attempting to shut down NAS at $TARGET_HOST..."

# Use -o BatchMode=yes to ensure it fails immediately if interaction is required.
ssh -o BatchMode=yes -o IdentityAgent=none -o IdentitiesOnly=yes -i "$KEY_PATH" "$TARGET_HOST" "shutdown -h now"

echo "Shutdown command sent to NAS."
