{ config, pkgs, lib, inputs, ... }:
let
  tpmLuksInitScript = pkgs.writeShellApplication {
    name = "tpm-luks-init";
    runtimeInputs = with pkgs; [
      cryptsetup
      tpm-tools
      coreutils
    ];
    text = ''
      RAW_KEY="/boot/tpm-luks.key"
      SEALED_KEY="/boot/tpm-luks.key.sealed"
      RECOVERY_PW="/boot/luks-recovery.password"

      # 生の鍵ファイルがあるか確認
      if [ ! -f "$RAW_KEY" ]; then
        echo "Raw key $RAW_KEY not found. Already initialized?"
        exit 0
      fi

      echo "Initializing TPM 1.2 sealing..."

      # 1. TPM 1.2 の所有権を取得 （N54Lではブート時にCMOSリセットが必要なので注意）
      # tpm_takeownership -z -y
      cp /var/lib/tpm/system.data /boot/system.data

      # 2. 各LUKSパーティションにこの生鍵を追加
      # (diskoが作ったスロット0のリカバリパスワードを使って、スロット1にこの鍵を入れる)
      for dev in /dev/disk/by-partlabel/disk-*; do
        if cryptsetup isLuks "$dev"; then
          echo "Registering key to $dev..."
          echo -n "$(cat "$RECOVERY_PW")" | cryptsetup luksAddKey "$dev" "$RAW_KEY" --key-file -
        fi
      done

      # 3. TPM 1.2 に封印
      # -z: Well-known auth (0000...)
      # -p 0: PCR 0 (BIOS/Firmware構成) に紐付け
      echo "Sealing key into TPM 1.2..."
      if tpm_sealdata -z -i "$RAW_KEY" -o "$SEALED_KEY"; then
        echo "Success: $SEALED_KEY created."

        # 3. 完了したら「生」のファイル群を削除
        rm "$RAW_KEY"
        # リカバリパスワードは、TPMが壊れた時のために残すか消すか選べますが、
        # 今回は方針通り削除します
        rm "$RECOVERY_PW"
        echo "Sensitive raw files removed."
      else
        echo "Error: TPM sealing failed!"
        exit 1
      fi
    '';
  };
  x540IrqAffinityScript = pkgs.writeShellApplication {
   name = "x540-irq-affinity";
   runtimeInputs = [
     pkgs.coreutils
    pkgs.ethtool
  ];
  text = ''
    ethtool -L enp2s0 combined 2

    # 割り込みを特定のコアに固定せず、分散を許可する（またはコアごとに分ける）
    # 一旦、すべてのコア(mask '3')で受け取れるようにするか、あるいは自動分散に任せる
    find /sys/class/net/enp2s0/device/msi_irqs/* -exec basename {} \; | while IFS= read -r irq; do
      echo 3 > /proc/irq/"$irq"/smp_affinity
      echo "Allowing IRQ $irq to use both CPUs (mask 3)"
    done
   '';
  };
in {
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
      kernelModules = [ "tpm_tis" "radeon" ];
      # 1. TPM 1.2 と VFAT (boot) のマウントに必要なモジュールを強制追加
      availableKernelModules = [ "tpm_tis" "uas" ];

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
    preLVMCommands = lib.mkOrder 500 ''
      # 1. ネットワークと名前解決の準備
      ip link set lo up
      echo "127.0.0.1 localhost" > /etc/hosts   # localhost の名前解決を確実にする
      mkdir -p /var/lib/tpm /etc /mnt-boot /var/run

      # 2. system.data の復元と、最初から完璧な権限設定
      mount -t ext4 /dev/disk/by-partlabel/disk-stick_usb2_in-boot /mnt-boot
      if [ -f /mnt-boot/system.data ]; then
        cp /mnt-boot/system.data /var/lib/tpm/system.data
        chown 0:0 /var/lib/tpm/system.data
        chmod 600 /var/lib/tpm/system.data
        chmod 700 /var/lib/tpm           # ディレクトリ自体を最初から 700 にしておく
      fi

      # 3. tcsd.conf の作成
      echo "system_ps_file = /var/lib/tpm/system.data" > /etc/tcsd.conf

      # 4. tcsd の起動
      echo "TPM-AUTO-UNLOCK: Starting tcsd..."
      tcsd -f -c /etc/tcsd.conf &
      TCSD_PID=$!

      # 5. デーモンが応答するまで最大 30秒待機するループ
      echo "TPM-AUTO-UNLOCK: Waiting for tcsd to respond..."
      CONNECTED=0
      for i in $(seq 1 30); do
        if tpm_version >/dev/null 2>&1; then
          echo "TPM-AUTO-UNLOCK: tcsd is READY after $i seconds."
          CONNECTED=1
          break
        fi
        sleep 1
      done

      # 6. 接続できた場合のみアンシールを実行
      if [ $CONNECTED -eq 1 ]; then
        echo "TPM-AUTO-UNLOCK: Attempting unseal..."
        RAW_KEY=$(tpm_unsealdata -z -i /mnt-boot/tpm-luks.key.sealed)
        if [ $? -eq 0 ] && [ -n "$RAW_KEY" ]; then
          echo "TPM-AUTO-UNLOCK: Unseal SUCCESS!"

          # バックグラウンドプロセスのIDを管理する配列（POSIXシェル用）
          PIDS=""

          for dev in /dev/disk/by-partlabel/disk-*; do
            if cryptsetup isLuks "$dev"; then
              # デバイスパスからラベル名を取得 (例: /dev/.../disk-stick_usb3_ex-nix -> disk-stick_usb3_ex-nix)
              LABEL="''${dev##*/}"

              # 先頭の "disk-" を削除 (-> stick_usb3_ex-nix)
              TEMP_NAME="''${LABEL#disk-}"

              # 最後のハイフンとその直後 (サフィックス) を削除 (-> stick_usb3_ex)
              # %-* は「最後に見つかるハイフンから後ろ」を切り捨てます
              BASE_NAME="''${TEMP_NAME%-*}"

              # NixOSが期待するマッパー名を作成
              MAP_NAME="luks_''${BASE_NAME}"

              echo "TPM-AUTO-UNLOCK: Starting open for $dev..."
              # サブシェル内で実行し、バックグラウンドへ
              (
                # パイプ経由で鍵を渡し、標準入力を確実に閉じる
                echo -n "$RAW_KEY" | cryptsetup open "$dev" "$MAP_NAME" --key-file=-
                echo "TPM-AUTO-UNLOCK: Finished $MAP_NAME"
              ) &
              PIDS="$PIDS $!"
            fi
          done

          # すべての cryptsetup プロセスが終了するまで待機
          echo "TPM-AUTO-UNLOCK: Waiting for all disks to unlock..."
          for pid in $PIDS; do
            wait "$pid"
          done

          unset RAW_KEY
        else
          echo "TPM-AUTO-UNLOCK: Unseal FAILED even with connection."
        fi
      else
        echo "TPM-AUTO-UNLOCK: TIMEOUT - tcsd never responded."
      fi

      kill $TCSD_PID
      umount /mnt-boot
    '';
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
      script = ''
        set +e

        echo "Applying IRQ Coalescing (ixgbe compatible)..."
        # ixgbeドライバ向けに、個別設定ではなく一括設定を試みます
        # 値を 1 にするとドライバ側で「適応型（Adaptive）」として扱われる場合があります
        ${pkgs.ethtool}/bin/ethtool -C enp2s0 rx-usecs 100 || echo "IRQ Coalescing failed, trying fallback..."
        ${pkgs.ethtool}/bin/ethtool -C enp2s0 rx-usecs 1 || echo "Adaptive fallback failed"

        echo "Setting MTU 9000..."
        # ip コマンドに pkgs.iproute2 を使用
        ${pkgs.iproute2}/bin/ip link set enp2s0 mtu 9000 || echo "MTU 9000 failed"

        echo "Applying Offload settings..."
        ${pkgs.ethtool}/bin/ethtool -K enp2s0 tso on gso on gro on lro on

        set -e
      '';
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