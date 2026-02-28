{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  tpmLuksInitScript = pkgs.writeShellApplication {
    name = "tpm-luks-init";
    runtimeInputs = with pkgs; [
      cryptsetup
      tpm-tools
      coreutils
    ];
    text = builtins.readFile ./tpm-luks-init.sh;
  };
  x540IrqAffinityScript = pkgs.writeShellApplication {
    name = "x540-irq-affinity";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ethtool
    ];
    text = builtins.readFile ./x540-irq-affinity.sh;
  };
in
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
  ];

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.linux-firmware ];

  powerManagement.cpuFreqGovernor = "ondemand";

  time.timeZone = "Asia/Tokyo";

  nixpkgs.config.allowUnfree = true;

  boot = {
    loader.grub = {
      enable = true;
      gfxmodeBios = "1280x800";
      extraConfig = ''
        set gfxpayload=keep
      '';
      configurationLimit = 8;
    };

    initrd = {
      kernelModules = [
        "tpm_tis"
        "radeon"
      ];
      # 1. TPM 1.2 と VFAT (boot) のマウントに必要なモジュールを強制追加
      availableKernelModules = [
        "tpm_tis"
        "uas"
      ];

      extraUtilsCommands = ''
        # 既存の tpm_unsealdata に加えて tpm_version を追加
        copy_bin_and_libs ${pkgs.tpm-tools}/bin/tpm_version
        copy_bin_and_libs ${pkgs.tpm-tools}/bin/tpm_unsealdata

        # trousers (TSS) から tcsd デーモンをコピー
        copy_bin_and_libs ${pkgs.trousers}/sbin/tcsd

        # (念のため) cryptsetup も含める (通常は自動で入りますが明示すると安心です)
        copy_bin_and_libs ${pkgs.cryptsetup}/bin/cryptsetup
      '';

      # 2. 自動解錠スクリプトの強化版
      # /dev/disk/by-partlabel/disk-stick_usb2_in-boot
      preLVMCommands = lib.mkOrder 500 (builtins.readFile ./pre-lvm-commands.sh);
    };
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
    hdparm
    htop
    sysstat
    ethtool
    iperf3

    tpm-tools
    tpm-quote-tools
    trousers
    cryptsetup
    openssl
    rng-tools
  ];

  services = {
    udev.extraRules = ''
        # HDD (回転メディア) に対してキューサイズを調整し、10分でスピンダウン
        SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ACTION=="add", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="8192", ATTR{queue/scheduler}="mq-deadline", RUN+="${lib.getExe pkgs.hdparm} -S 120 /dev/%k"

      # SSD (sda, sdb等) に対してスケジューラを none に設定
      ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"

      # 書き込みリクエストのキューサイズを増やす (デフォルト128 -> 1024)
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/nr_requests}="1024"

      # 暗号化デバイスの先読みを大きくして I/O 回数を減らす
      ACTION=="add|change", KERNEL=="dm-*", ATTR{queue/read_ahead_kb}="4096"
    '';

    tcsd.enable = true;

    irqbalance.enable = false;

    openssh = {
      enable = true;
      settings = {
        # 1. root ログインを（証明書や鍵なら）許可する
        PermitRootLogin = "prohibit-password";

        # 2. 指定した CA 公開鍵で署名された証明書を信頼する
        # 公開鍵の文字列をファイルとして書き出し、そのパスを渡す
        TrustedUserCAKeys = "${pkgs.writeText "ssh-ca-key.pub" ''
          ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFxXpsKHNwT8S6dzmNqsmNRRLFGw0Ss3RG1iHC+pWN6G NAS_SSH_CA
        ''}";
      };
    };

    fstrim = {
      enable = true;
      interval = "Sun *-*-* 03:00:00";
    };

    iperf3 = {
      enable = true;
      openFirewall = true;
    };
  };

  networking = {
    hostName = "nas";
    hostId = "8425e349";
    firewall.enable = true;
    firewall.allowPing = true;
  };

  systemd.services = {
    "irq-affinity-x540" = {
      enable = true;
      description = "Pin Intel X540 IRQs to CPU0";

      # after だけでなく、依存関係を明示的に追加して警告を解消
      wants = [ "network-online.target" ];
      after = [
        "local-fs.target"
        "network-online.target"
      ];

      script = "${lib.getExe x540IrqAffinityScript}";

      serviceConfig = {
        Type = "oneshot";
        # 1回実行して成功したら、プロセスが終了しても「起動中」とみなす
        RemainAfterExit = true;
      };

      # default.target よりも multi-user.target の方がサーバー用途では一般的
      wantedBy = [ "multi-user.target" ];
    };

    "10gbe-optimization" = {
      description = "Optimize Intel 10GbE NIC";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.ethtool
        pkgs.iproute2
        pkgs.bash
      ];
      script = builtins.readFile ./10gbe-optimization.sh;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    tpm-luks-init = {
      description = "Initialize TPM LUKS Sealing";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tpmLuksInitScript}/bin/tpm-luks-init";
        RemainAfterExit = true;
      };
      # 既に完了フラグがあれば動かないようにする設定
      unitConfig.ConditionPathExists = "!/etc/tpm-luks-init-done";
    };

    samba-smbd.serviceConfig = {
      AllowedCPUs = "1";
    };
  };

  users = {
    # mutableUsers = false;
    # users.root = {
    #   hashedPassword = "$y$j9T$F41h0lJQ.fQ5IcsRjdM/g0$kb9vTzYh.9LMj4yUnN4AnVzEG/sWGG9cJRwpIdFoM7D";
    #   openssh.authorizedKeys.keys = [
    #     "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAxFVnSmn+31h/6+/XqAmRDxD5pdIBNlDAmLiETajdEI+RsqSRj+mEu3ibK30NNE/32HBk45u4iYOrknSeVmW/k="
    #   ];
    # };
  };

  # system.stateVersion = "25.11";
}
