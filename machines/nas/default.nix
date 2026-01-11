{ config, pkgs, lib, inputs, ... }:
let 
  x540IrqAffinityScript = pkgs.writeShellApplication {
   name = "x540-irq-affinity";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ethtool
    ];
   text = ''
    find /sys/class/net/enp2s0/device/msi_irqs/* -exec basename {} \; | while IFS= read -r irq; do
      echo 1 > /proc/irq/"$irq"/smp_affinity
      echo set /proc/irq/"$irq"/smp_affinity to 1
    done
    ethtool -L enp2s0 combined 1
    '';
  };
in {
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
  ];

  hardware.enableRedistributableFirmware = true;

  time.timeZone = "Asia/Tokyo";

  boot.initrd.availableKernelModules = [ "uas" ]; # /nix が UASPをサポートしたインタフェースにマウントされるので必要
  boot.blacklistedKernelModules = [ "radeon" ]; # ブートシーケンスの途中でコンソールの表示の更新が止まる対策
  boot.kernelParams = [
    "usbcore.autosuspend=-1"
    "nomodeset" # ブートシーケンスの途中でコンソールの表示の更新が止まる対策
    #"loglevel=7"
    #"systemd.log_level=debug"
    #"systemd.log_target=console" # トラブルシューティングに役に立つことがあるためコンソールに出力する
  ];
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 268435456;
    "net.core.wmem_max" = 268435456;
    "net.ipv4.tcp_rmem" = "4096 87380 268435456";
    "net.ipv4.tcp_wmem" = "4096 65536 268435456";
    "net.core.netdev_max_backlog" = 5000;

    "vm.dirty_ratio" = 20;
    "vm.dirty_background_ratio" = 10;

    "kernel.sched_autogroup_enabled" = 0;
    "net.core.netdev_budget" = 600;
    "net.core.netdev_budget_usecs" = 8000;
  };

  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
    tree
    lsof
    inotify-tools
    rsync

    # hardware investigation & performance monitoring tools
    pciutils
    usbutils
    smartmontools
    htop
    sysstat
    ethtool
    iperf3
  ];

  services.udev.extraRules = ''
    SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ACTION=="add", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="8192", ATTR{queue/scheduler}="mq-deadline"
  '';

  networking = {
    hostName = "nas";
    hostId = "8425e349";
    firewall.enable = true;
    firewall.allowPing = true;
  };

  systemd.services."irq-affinity-x540" = {
    enable = true;
    description = "Pin Intel X540 IRQs to CPU0";
    after = [ 
      "local-fs.target"
      "network-online.target"
    ];
    script = "${lib.getExe x540IrqAffinityScript}";
    serviceConfig = {
      Type = "oneshot";
    };
    wantedBy = [ "default.target" ];
  };

  systemd.services.samba-smbd.serviceConfig = {
    AllowedCPUs = "1";
  };

  services.irqbalance.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  services.fstrim = {
    enable = true;
    interval = "Sun *-*-* 03:00:00";
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