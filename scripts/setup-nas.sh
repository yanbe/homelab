#!/bin/sh
# ./scripts/create-nas-secrets.sh
nix run github:nix-community/nixos-anywhere --extra-experimental-features 'nix-command flakes' -- --flake '.#nas' --generate-hardware-config nixos-facter ./machines/nas/facter.json --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null --disk-encryption-keys /boot/luks-recovery.password ./secrets/nas/boot/luks-recovery.password --extra-files ./secrets/nas --debug --phases kexec,disko,install root@192.168.1.25
