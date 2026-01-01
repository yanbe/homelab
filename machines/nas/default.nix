{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
  ];

  hardware.enableRedistributableFirmware = true;

  time.timeZone = "Asia/Tokyo";

  boot.initrd.availableKernelModules = [ "uas" ];
  boot.blacklistedKernelModules = [ "radeon" ]; # ブートシーケンスの途中でコンソールの表示の更新が止まる対策
  boot.kernelParams = [
    "usbcore.autosuspend=-1"
    "nomodeset" # ブートシーケンスの途中でコンソールの表示の更新が止まる対策
    #"loglevel=7"
    #"systemd.log_level=debug"
    "systemd.log_target=console" # トラブルシューティングに役に立つことがあるためコンソールに出力する
  ];
  boot.kernel.sysctl = {
    # TCP ウィンドウチューニング (Robocopy MT:16-32向け)
    "net.core.rmem_max"     = 134217728;     # 128MB
    "net.core.wmem_max"     = 134217728;
    "net.ipv4.tcp_rmem"     = "4096 87380 134217728";
    "net.ipv4.tcp_wmem"     = "4096 65536 134217728";
    "net.core.netdev_max_backlog" = 3000;

    "vm.dirty_background_bytes"    = 2147483648; # 2GB
    "vm.dirty_bytes"               = 8589934592; # 8GB
    "vm.dirty_writeback_centisecs" = 1500;       # 15秒
    "vm.dirty_expire_centisecs"    = 60000;      # 10分
  };

  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
    pciutils
    usbutils
    smartmontools
    htop
    sysstat
    ethtool
    iperf3
  ];

  networking = {
    hostName = "nas";
    hostId = "8425e349";
    firewall.enable = true;
    firewall.allowPing = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  users = {
    # mutableUsers = false;
    users.root = {
      hashedPassword = "$y$j9T$F41h0lJQ.fQ5IcsRjdM/g0$kb9vTzYh.9LMj4yUnN4AnVzEG/sWGG9cJRwpIdFoM7D";
      openssh.authorizedKeys.keys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAxFVnSmn+31h/6+/XqAmRDxD5pdIBNlDAmLiETajdEI+RsqSRj+mEu3ibK30NNE/32HBk45u4iYOrknSeVmW/k="
      ];
    };
  };

  system.stateVersion = "25.11";
}