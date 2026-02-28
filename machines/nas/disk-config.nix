{ lib, ... }:
let
  luksLayout = name: innerContent: {
    type = "luks";
    name = "luks_${name}";

    # 1. 暗号化方式（Adiantum）の指定
    extraFormatArgs = [
      "--cipher"
      "'capi:adiantum(xchacha12,aes)-plain64'"
      "--key-size"
      "256"
      "--iter-time"
      "2000" # パスワード照合時間を2秒に固定（N54Lの負荷軽減）
    ];

    # 2. 開封時のオプション
    extraOpenArgs = [
      "--allow-discards"
      "--perf-no_read_workqueue"
      "--perf-no_write_workqueue"
    ];

    settings = {
      allowDiscards = true;
      # bypassWorkqueues = true; # ← これをコメントアウトまたは削除します

      # 以下の2つを追加することで、マルチコアでの並列暗号化を有効にします
      crypttabExtraOpts = [
        "same-cpu-crypt"
        "submit-from-read-cpu"
      ];
    };
    content = innerContent;
  };
  ssd_f2fs = name: device: {
    ${name} = {
      device = device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          data = {
            size = "100%";
            content = luksLayout name {
              type = "filesystem";
              format = "f2fs";
              mountpoint = "/mnt/ssd/${name}";
              extraArgs = [
                # f2fs mkfs f2fs-specific flags:
                "-O"
                "extra_attr,inode_checksum,sb_checksum,compression"
              ];
              mountOptions = [
                # f2fs マウント最適化パラメータ
                "atgc"
                "gc_merge"
                "background_gc=on"
                "nodiscard" # services.fstrim で明示的に TRIMをおこなう
                "flush_merge"
                "lazytime"
                "noatime"
                "nodiratime"
                "user_xattr"
                "nofail"
                "private"
                "inline_data"
                "inline_dentry"
                "active_logs=6"
                "checkpoint_merge"
              ];
            };
          };
        };
      };
    };
  };
  hdd_xfs = name: device: {
    ${name} = {
      device = device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          data = {
            size = "100%";
            content = luksLayout name {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/mnt/hdd/${name}";
              extraArgs = [
                # mkfs.xfs に渡す追加オプション
                "-m"
                "crc=1" # metadata CRC を有効化（推奨）
                "-m"
                "finobt=1" # free inode btree を有効化
              ]
              ++ lib.lists.optionals (lib.hasInfix "pmp" name) [
                "-d"
                "agcount=16"
              ];
              mountOptions = [
                # マウント時のパフォーマンスオプション
                "noatime"
                "nodiratime"
                "inode64"
                "logbufs=8"
                "logbsize=256k"
                "allocsize=512m"
                "nofail"
                "private"
              ];
            };
          };
        };
      };
    };
  };
in
{
  disko.devices = {
    # {deviceType}_{connectionType}(_{specialUsage})(_{protocol})_{port}
    disk = {
      stick_usb2_in = {
        device = "/dev/disk/by-id/usb-BUFFALO_ClipDrive_408183A840A2D8B2-0:0";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            BOOT = {
              priority = 1;
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            boot = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
      stick_usb3_ex = {
        device = "/dev/disk/by-id/usb-Logitec_LMD_USB_Device_5AA690500024A-0:0";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            nix = {
              size = "100%";
              content = luksLayout "stick_usb3_ex" {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
    }
    // ssd_f2fs "sata_p0" "/dev/disk/by-id/ata-INTEL_SSDSC2CT120A3_CVMP229202QL120BGN"
    // ssd_f2fs "sata_p1" "/dev/disk/by-id/ata-Samsung_SSD_750_EVO_120GB_S3F2NWAHC24663H"
    // ssd_f2fs "sata_p2" "/dev/disk/by-id/ata-Samsung_SSD_750_EVO_120GB_S2SGNWAH267962P"
    // ssd_f2fs "sata_p3" "/dev/disk/by-id/ata-Samsung_SSD_750_EVO_120GB_S3F2NWAHC04260K"
    # ssd_sata_p4 はない: esata(PMP)の中で最初に認識されたデバイス(接続状況によって不定)がBIOSからsata_p4になるので欠番にしている

    // ssd_f2fs "usb3_uas_p5" "/dev/disk/by-id/ata-ORICO_UB202412100698"
    // hdd_xfs "sata_parity_p5" "/dev/disk/by-id/ata-ST2000DL003-9VT166_5YD5AHQ8"

    # 裸族のスカイタワー10BayはeSATA・USBともには自分の環境ではコントローラーごとに４台ずつ計８台までしか安定して認識されない
    // hdd_xfs "esata_parity_pmp_p0" "/dev/disk/by-id/ata-WDC_WD20EARS-00S8B1_WD-WCAVY2626056"
    // hdd_xfs "esata_pmp_p1" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WMAZA2671006"
    // hdd_xfs "esata_pmp_p2" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WCAZA0260439"
    // hdd_xfs "esata_pmp_p3" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WMAZA3492202"

    // hdd_xfs "esata_pmp_p5" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC06839"
    // hdd_xfs "esata_pmp_p6" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WCAZA0146677"
    // hdd_xfs "esata_pmp_p7" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC07024"
    // hdd_xfs "esata_pmp_p8" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC07059"

    // hdd_xfs "usb3_bot_p0" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC07027"
    // hdd_xfs "usb3_bot_p1" "/dev/disk/by-id/ata-SAMSUNG_HD103SJ_S246JD6ZC02757"
    // hdd_xfs "usb3_bot_p2" "/dev/disk/by-id/ata-MB0500EBNCR_WMAYP0E80UEX";
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=2G"
        "defaults"
        "mode=755"
        "private"
      ];
    };
  };

  environment.persistence."/nix/persistent" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      #"/var/log" # for boot truble investigation purpose only
      "/var/lib/tpm"
      "/var/lib/samba"
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/tpm-luks-init-done"
    ];
  };
}
