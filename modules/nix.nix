{ config, ... }:
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "nixos" "yanbe" ];
    # Fallback to building from source when cache server is not accessible.
    fallback = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
    persistent = true;
  };
}