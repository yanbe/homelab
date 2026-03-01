#!/usr/bin/env bash
set -euo pipefail

# 毎回 update しない！
# アップデートしたい時だけ手動で `nix flake update` を叩く
# sudo nix flake update --extra-experimental-features 'nix-command flakes'

KEY_PATH="${KEY_PATH:-$HOME/.ssh/id_nas_fido_ecdsa_sk}"
CERT_PATH="${CERT_PATH:-${KEY_PATH}-cert.pub}"
TARGET_HOST="${TARGET_HOST:-root@nas.local}"
CONTROL_PATH="${CONTROL_PATH:-$HOME/.ssh/cm-%r@%h:%p}"
NIX_SSHOPTS_VALUE="${NIX_SSHOPTS_VALUE:--F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -i $KEY_PATH -o CertificateFile=$CERT_PATH -o ControlMaster=auto -o ControlPersist=5m -o ControlPath=$CONTROL_PATH}"

log() {
  echo "[update-nas] $*"
}

if [[ ! -f "$KEY_PATH" ]]; then
  echo "FIDO key not found: $KEY_PATH" >&2
  echo "Create it with: ssh-keygen -t ecdsa-sk -f $KEY_PATH" >&2
  exit 1
fi

if [[ ! -f "$CERT_PATH" ]]; then
  echo "SSH certificate not found: $CERT_PATH" >&2
  echo "Issue it with your CA key (example):" >&2
  echo "  ssh-keygen -s ~/ssh-ca/ssh_ca_key -I \"nas-fido-$(date +%F)\" -n root -V +52w ${KEY_PATH}.pub" >&2
  exit 1
fi

log "Forcing FIDO key+certificate only (ignoring ssh-agent and default ssh config)."

log "Checking FIDO authentication to $TARGET_HOST (explicit touch step)"
log "If prompted, touch your fingerprint key now."
ssh \
  -F /dev/null \
  -o IdentityAgent=none \
  -o ControlMaster=auto \
  -o ControlPersist=5m \
  -o ControlPath="$CONTROL_PATH" \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -i "$KEY_PATH" \
  -o CertificateFile="$CERT_PATH" \
  "$TARGET_HOST" "echo FIDO_OK" >/dev/null
log "FIDO auth check passed. Reusing SSH connection for nixos-rebuild."

log "Running nixos-rebuild (normally no second touch prompt)."
log "NIX_SSHOPTS: $NIX_SSHOPTS_VALUE"
SSH_AUTH_SOCK=NIX_SSHOPTS="$NIX_SSHOPTS_VALUE" nixos-rebuild switch --flake .#nas --target-host "$TARGET_HOST"
