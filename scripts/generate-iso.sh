sudo nix flake update --extra-experimental-features 'nix-command flakes'
nix build --extra-experimental-features 'nix-command flakes' .#minimal-install-iso
