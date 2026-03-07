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
  outputs =
    { self, ... }@inputs:
    let
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      machineConfigurations = import ./machines/flake.nix { inherit inputs; };
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = with pkgs; [
          nil
          nixfmt-rfc-style
          shellcheck
          bash-language-server
        ];
      };

      minimal-install-iso = inputs.nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./machines/nas/kernel.nix
          ./generators/minimal.nix
        ];
        specialArgs = { inherit inputs; };
        format = "install-iso";
      };
      nixosConfigurations = machineConfigurations;
    };
}
