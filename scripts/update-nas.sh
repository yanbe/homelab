sudo nix flake update --extra-experimental-features 'nix-command flakes'
nixos-rebuild switch --flake .#nas --target-host root@nas.local