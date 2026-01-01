{
  description = "NixOS flake for my dotfiles";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    }; 
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    impermanence.url = "github:nix-community/impermanence";
  };
  outputs = { self, ... } @inputs: {
    minimal-install-iso = inputs.nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      modules = [ ./generators/minimal.nix ];
      specialArgs = { inherit inputs; };
      format = "install-iso";
    };
    nixosConfigurations.nas = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./machines/nas
        ./machines/nas/storage.nix
        ./machines/nas/samba.nix
      ];
      specialArgs = { inherit inputs; };
    };
  };
}