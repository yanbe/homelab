{ inputs }:
let
  lib = inputs.nixpkgs.lib;
  mkSystem =
    modules:
    lib.nixosSystem {
      system = "x86_64-linux";
      inherit modules;
      specialArgs = { inherit inputs; };
    };
in
{
  nas = mkSystem [
    ./nas
    ./nas/kernel.nix
    ./nas/disk-config.nix
    ./nas/mergerfs.nix
    ./nas/snapraid.nix
    ./nas/samba.nix
  ];

  incus = mkSystem [
    ./incus
  ];

  nixos-dev = mkSystem [
    ./nixos-dev
  ];
}
