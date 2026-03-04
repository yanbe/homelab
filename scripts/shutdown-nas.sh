#!/usr/bin/env bash
# scripts/suspend-nas.sh
# Sends a suspend command to the NAS via SSH using the automation key.

TARGET_IP="192.168.1.154"
TARGET_HOST="root@$TARGET_IP"
KEY_PATH="$HOME/.ssh/id_nas_automation"

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Automation key not found: $KEY_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Attempting to shut down NAS at $TARGET_HOST..."

# Use a retry loop for better reliability in case of transient network issues.
MAX_RETRIES=3
for ((i=1; i<=MAX_RETRIES; i++)); do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o IdentityAgent=none -o IdentitiesOnly=yes -i "$KEY_PATH" "$TARGET_HOST" "shutdown -h now"; then
    echo "Shutdown command successfully sent to NAS."
    "$SCRIPT_DIR/log-power-event.sh" "Shutdown" "Automation" "Success" "NAS shutdown command accepted."
    exit 0
  fi
  echo "Attempt $i failed. Retrying..."
  sleep 2
done

echo "Failed to send shutdown command after $MAX_RETRIES attempts." >&2
"$SCRIPT_DIR/log-power-event.sh" "Shutdown" "Automation" "Failure" "All retries failed (No route to host or SSH timeout)."
exit 1
