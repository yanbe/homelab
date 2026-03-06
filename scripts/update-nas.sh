#!/usr/bin/env bash
set -euo pipefail

# 毎回 update しない！
# アップデートしたい時だけ手動で `nix flake update` を叩く
# sudo nix flake update --extra-experimental-features 'nix-command flakes'

KEY_PATH="${KEY_PATH:-$HOME/.ssh/id_nas_automation}"
CERT_PATH="${CERT_PATH:-${KEY_PATH}-cert.pub}"
TARGET_HOST="${TARGET_HOST:-root@nas.local}"
CONTROL_PATH="${CONTROL_PATH:-$HOME/.ssh/cm-%r@%h:%p}"
NIX_SSHOPTS_VALUE="${NIX_SSHOPTS_VALUE:--F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -i $KEY_PATH -o CertificateFile=$CERT_PATH -o ControlMaster=auto -o ControlPersist=5m -o ControlPath=$CONTROL_PATH}"

log() {
  echo "[update-nas] $*"
}

if [[ ! -f "$KEY_PATH" ]]; then
  echo "SSH key not found: $KEY_PATH" >&2
  exit 1
fi

# Fallback configuration
TEST_KEY="$KEY_PATH"

log "----- USB/IP FIDO Key Setup -----"
log "If your FIDO key is missing, you can attach it from Windows using:"
log "  usbipd wsl attach --busid <id>"
log "List devices with: usbipd wsl list"
log "-----------------------------------"

# If the FIDO key is explicitly defined or attached, we attempt to use it first.
FIDO_KEY_PATH="$HOME/.ssh/id_nas_fido_ecdsa_sk"
if [[ -f "$FIDO_KEY_PATH" ]]; then
  log "Checking FIDO authentication to $TARGET_HOST (explicit touch step)"
  log "If prompted, touch your fingerprint key now. (Timeout 10s)"
  if timeout 10 ssh \
    -F /dev/null \
    -o IdentityAgent=none \
    -o ControlMaster=auto \
    -o ControlPersist=5m \
    -o ControlPath="$CONTROL_PATH" \
    -o IdentitiesOnly=yes \
    -o PreferredAuthentications=publickey \
    -o PasswordAuthentication=no \
    -i "$FIDO_KEY_PATH" \
    -o CertificateFile="$FIDO_KEY_PATH-cert.pub" \
    "$TARGET_HOST" "echo FIDO_OK" >/dev/null 2>&1; then
    log "FIDO auth check passed. Using FIDO key for deployment."
    TEST_KEY="$FIDO_KEY_PATH"
    NIX_SSHOPTS_VALUE="-F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -i $FIDO_KEY_PATH -o CertificateFile=$FIDO_KEY_PATH-cert.pub -o ControlMaster=auto -o ControlPersist=5m -o ControlPath=$CONTROL_PATH"
  else
    log "WARNING: FIDO key check failed or timed out. Falling back to automation key ($KEY_PATH)."
  fi
fi

log "Running nixos-rebuild with key: $TEST_KEY"
log "NIX_SSHOPTS: $NIX_SSHOPTS_VALUE"

# Retry loop for deployment in case of transient SSH/network failures
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
  log "Attempt $i/$MAX_RETRIES..."
  if SSH_AUTH_SOCK="" NIX_SSHOPTS="$NIX_SSHOPTS_VALUE" nixos-rebuild switch --flake .#nas --target-host "$TARGET_HOST"; then
    log "Deployment successful!"
    exit 0
  fi
  if [[ $i -lt $MAX_RETRIES ]]; then
    log "Deployment failed. Retrying in 5 seconds..."
    sleep 5
  fi
done

log "ERROR: Deployment failed after $MAX_RETRIES attempts."
exit 1
