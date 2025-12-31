{ inputs, ... }:
{
  # TODO: Increase tmpfs mount size on /nix/.rw-store

  # imports = [
  #   inputs.disko.nixosModules.disko
  # ];

  networking.hostName = "minimal";

  # Expand rw store a bit.

  # virtualisation.diskSize = 2 * 1024; # 2G

  # disko.devices.nodev = {
  #   "/nix/.rw-store" = {
  #     fsType = "tmpfs";
  #     mountOptions = [
  #       "size=2G"
  #       "mode=755"
  #     ];
  #   };
  # };

  # fileSystems."/nix/.rw-store" = {
  #   device = "none";
  #   fsType = "tmpfs";
  #   options = [
  #     "size=512M"
  #     "mode=755"
  #   ];
  # };

  system.nixos.variant_id = "installer";

  boot.kernelParams = [ "console=tty0" ];
  # Disable sudo as we've no non-root users.
  security.sudo.enable = false;

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAxFVnSmn+31h/6+/XqAmRDxD5pdIBNlDAmLiETajdEI+RsqSRj+mEu3ibK30NNE/32HBk45u4iYOrknSeVmW/k="
  ];

  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
    openFirewall = true;
  };
  
  powerManagement.cpuFreqGovernor = "performance";
  zramSwap = {
    enable = true;
    memoryPercent = 300;
  };

  nix.settings = {
    auto-optimise-store = true;
    substituters = [
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?
}
