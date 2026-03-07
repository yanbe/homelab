{
  modulesPath,
  pkgs,
  ...
}:
let
  automationKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDg/I8PnP4P9EBVTazW1oL1E8rYj0dzQ0bHQ3k8a06wu nas-automation";
in
{
  imports = [
    "${modulesPath}/virtualisation/incus-virtual-machine.nix"
    ../../modules/nix.nix
    ./kernel.nix
    ./tooling.nix
  ];

  networking = {
    hostName = "nixos-dev";
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
    firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  systemd.network = {
    enable = true;
    networks."50-enp5s0" = {
      matchConfig.Name = "enp5s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  time.timeZone = "Asia/Tokyo";

  users.users.root.openssh.authorizedKeys.keys = [ automationKey ];
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ automationKey ];
    shell = pkgs.bashInteractive;
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      UseDns = false;
    };
  };

  system.stateVersion = "26.05";
}
