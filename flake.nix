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
      modules = [ 
        ./machines/nas/kernel.nix
        ./generators/minimal.nix 
      ];
      specialArgs = { inherit inputs; };
      format = "install-iso";
    };
    nixosConfigurations.nas = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          # 常に LTS (6.18系など) を使うようにすれば、
          # unstable チャンネルの中でもカーネルの更新頻度が下がり、ビルド回数を減らせます
          boot.kernelPackages = pkgs.linuxPackages_6_18;
        })
        ./machines/nas
        ./machines/nas/kernel.nix
        ./machines/nas/disk-config.nix
        ./machines/nas/mergerfs.nix
        ./machines/nas/snapraid.nix
        ./machines/nas/samba.nix
      ];
      specialArgs = { inherit inputs; };
    };
    nixosConfigurations.incus = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./machines/incus
      ];
      specialArgs = { inherit inputs; };
    };
  };
}