{ config, pkgs, lib, inputs, ... }:
let 
  tpmLuksInitScript = pkgs.writeShellApplication {
    name = "tpm-luks-init";
    runtimeInputs = with pkgs; [
      cryptsetup
      tpm-tools
      coreutils # mkdir, touch, rm など
    ];
    text = ''
      MASTER_KEY="/etc/tpm-init/master.key"
      TEMP_PW="/etc/luks-secret.password"
      DONE_FLAG="/nix/persistent/etc/tpm-luks-init-done"

      # 鍵が存在しない、または既に実行済みの場合は終了
      if [ ! -f "$MASTER_KEY" ]; then
        echo "Master key not found at $MASTER_KEY. Skipping."
        exit 0
      fi

      echo "Starting TPM-LUKS initialization..."

      # 1. 全ての LUKS パーティションにマスターキーを追加登録
      # /dev/disk/by-partlabel/* をスキャン (disko の命名規則を利用)
      for dev in /dev/disk/by-partlabel/*; do
        if cryptsetup isLuks "$dev"; then
          echo "Adding master key to $dev..."
          # 初回は送り込んだ一時パスワード (--extra-files) で解錠して鍵を追加
          cryptsetup luksAddKey "$dev" "$MASTER_KEY" --key-file "$TEMP_PW"
        fi
      done

      # 2. TPM 1.2 にマスターキーを封印して /boot に保存
      # -z: well-known(全ゼロ)パスワード, -p 0: PCR 0(BIOS構成)に拘束
      echo "Sealing master key to TPM 1.2..."
      tpm_sealdata -z -p 0 -i "$MASTER_KEY" -o /boot/master.key.sealed

      # 3. 完了処理
      mkdir -p "$(dirname "$DONE_FLAG")"
      touch "$DONE_FLAG"
      
      # 安全のため NAS 上の生鍵と一時パスワードを削除
      rm "$MASTER_KEY"
      rm "$TEMP_PW"
      echo "TPM-LUKS initialization completed successfully."
    '';
  };
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

  nixpkgs.config.allowUnfree = true;
  boot.initrd.availableKernelModules = [ "uas" "radeon" ]; # /nix が UASPをサポートしたインタフェースにマウントされるので必要
  boot.blacklistedKernelModules = [ "amdgpu" ]; # ブートシーケンスの途中でコンソールの表示の更新が止まる対策
  boot.kernelParams = [
    "usbcore.autosuspend=-1"
    "radeon.modeset=1"
  ];
  hardware.firmware = [ pkgs.linux-firmware ];
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

  services.tcsd.enable = true;

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

    tpm-tools
    tpm-quote-tools
    cryptsetup
    openssl
    rng-tools
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

  systemd.services.tpm-luks-init = {
    description = "Initial TPM LUKS Sealing (Run once)";
    after = [ "dev-tpm0.device" ];
    wantedBy = [ "multi-user.target" ];
    
    # 永続領域にフラグがない場合のみ実行
    unitConfig.ConditionPathExists = "!/nix/persistent/etc/tpm-luks-init-done";
    script = "${lib.getExe tpmLuksInitScript}";

    serviceConfig = {
      Type = "oneshot";
      # 生成された shell application を実行
      RemainAfterExit = true;
    };
  };

  systemd.services.samba-smbd.serviceConfig = {
    AllowedCPUs = "1";
  };

  services.irqbalance.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      # 従来のパスワード認証などはオフにする
      PasswordAuthentication = false;
    };
    # 送り込んだCA公開鍵を指定
    extraConfig = ''
      TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
    '';
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
    # users.root = {
    #   hashedPassword = "$y$j9T$F41h0lJQ.fQ5IcsRjdM/g0$kb9vTzYh.9LMj4yUnN4AnVzEG/sWGG9cJRwpIdFoM7D";
    #   openssh.authorizedKeys.keys = [
    #     "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAxFVnSmn+31h/6+/XqAmRDxD5pdIBNlDAmLiETajdEI+RsqSRj+mEu3ibK30NNE/32HBk45u4iYOrknSeVmW/k="
    #   ];
    # };
  };

  # system.stateVersion = "25.11";
}